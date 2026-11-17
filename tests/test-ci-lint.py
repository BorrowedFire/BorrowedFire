#!/usr/bin/env python3
"""ci-lint flags wasteful private-repo workflows and never blocks the session update check."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / 'tools'


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, TOOLS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


lint = load('ci_lint', 'ci-lint.py')
sync = load('sync', 'sync-fleet.py')

GOOD_CONCURRENCY = """\
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
"""

COMPLIANT = """\
name: CI
on:
  pull_request:
  push:
    branches: [main]
""" + GOOD_CONCURRENCY + """\
jobs:
  test:
    runs-on: [self-hosted, studio]
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: |
          echo "runs-on: ubuntu-latest # not a job key"
"""


class CheckTests(unittest.TestCase):
    def test_compliant_workflow_passes(self):
        self.assertEqual(lint.check_workflow(COMPLIANT), [])

    def test_missing_concurrency_is_flagged(self):
        problems = lint.check_workflow(COMPLIANT.replace(GOOD_CONCURRENCY, ''))
        self.assertEqual(problems, ['runs on pull requests without the PR-only concurrency block'])

    def test_plain_cancel_true_is_flagged(self):
        # true would also cancel default-branch runs, which the rule forbids.
        text = COMPLIANT.replace("${{ github.event_name == 'pull_request' }}", 'true')
        problems = lint.check_workflow(text)
        self.assertEqual(len(problems), 1)
        self.assertIn("cancel-in-progress is 'true'", problems[0])

    def test_group_without_workflow_name_is_flagged(self):
        problems = lint.check_workflow(COMPLIANT.replace('${{ github.workflow }}-', 'ci-'))
        self.assertEqual(problems, ['concurrency group must include github.workflow and github.ref'])

    def test_hosted_and_partial_runners_are_flagged(self):
        for runs_on in ('ubuntu-latest', '[self-hosted]', '[self-hosted, studio, macOS]',
                        '${{ matrix.os }}', '\n      - self-hosted\n      - linux'):
            with self.subTest(runs_on=runs_on):
                problems = lint.check_workflow(COMPLIANT.replace('[self-hosted, studio]', runs_on))
                self.assertEqual(len(problems), 1)
                self.assertTrue(problems[0].startswith('job test runs-on'))

    def test_equivalent_spellings_pass(self):
        variants = [
            COMPLIANT.replace('[self-hosted, studio]', '\n      - self-hosted\n      - "studio"'),
            COMPLIANT.replace('[self-hosted, studio]', '[studio, self-hosted]'),
            COMPLIANT.replace("${{ github.event_name == 'pull_request' }}",
                              "\"${{ github.event_name == 'pull_request' }}\""),
            COMPLIANT.replace('on:\n  pull_request:\n  push:\n    branches: [main]\n', 'on: [pull_request, push]\n'),
        ]
        for text in variants:
            with self.subTest(text=text):
                self.assertEqual(lint.check_workflow(text), [])

    def test_flow_mappings_are_read(self):
        cases = {
            'on: {pull_request: {}}\njobs:\n  t:\n    runs-on: [self-hosted, studio]\n':
                ['runs on pull requests without the PR-only concurrency block'],
            'on: push\njobs: {build: {runs-on: ubuntu-latest}}\n':
                ['job build runs-on "ubuntu-latest"; must be [self-hosted, studio]'],
            'on: push\njobs:\n  build: {runs-on: ubuntu-latest}\n':
                ['job build runs-on "ubuntu-latest"; must be [self-hosted, studio]'],
            COMPLIANT.replace(GOOD_CONCURRENCY, 'concurrency: {group: ${{ github.workflow }}-${{ github.ref }}, '
                              "cancel-in-progress: ${{ github.event_name == 'pull_request' }}}\n"): [],
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(lint.check_workflow(text), expected)

    def test_unsupported_forms_are_errors_not_passes(self):
        for text in ('jobs:\n  t:\n    runs-on: [self-hosted, studio]\n',
                     'on: !custom push\njobs:\n  t:\n    runs-on: [self-hosted, studio]\n',
                     'on: *missing\njobs:\n  t:\n    runs-on: [self-hosted, studio]\n'):
            with self.subTest(text=text), self.assertRaises(lint.ParseError):
                lint.check_workflow(text)

    def test_valid_layouts_read_like_yaml(self):
        variants = [
            # A closing bracket on its own line at the key's indent.
            COMPLIANT.replace('[self-hosted, studio]', '[self-hosted, studio,\n    ]'),
            # A nested flow sequence elsewhere in the file.
            COMPLIANT.replace('branches: [main]', 'branches: [[main]]'),
            # An anchored runs-on reused through an alias.
            COMPLIANT.replace('[self-hosted, studio]', '&studio [self-hosted, studio]')
            + '  lint:\n    runs-on: *studio\n    steps: []\n',
        ]
        for text in variants:
            with self.subTest(text=text):
                self.assertEqual(lint.check_workflow(text), [])

    def test_multiline_flow_sequences_are_parsed_or_rejected(self):
        # A trigger list split across lines must still be read as a list of events.
        missing = COMPLIANT.replace(GOOD_CONCURRENCY, '').replace(
            'on:\n  pull_request:\n  push:\n    branches: [main]\n', 'on: [push,\n  pull_request]\n')
        self.assertEqual(lint.check_workflow(missing),
                         ['runs on pull requests without the PR-only concurrency block'])
        split_runner = COMPLIANT.replace('[self-hosted, studio]', '[self-hosted,\n      studio]')
        self.assertEqual(lint.check_workflow(split_runner), [])
        for value in ('[push, pull_request', '[push, [pull_request]]', '[push, {a: b}]',
                      '[push] extra', '[push,, pull_request]', '[push,\n  pull_request'):
            with self.subTest(value=value), self.assertRaises(lint.ParseError):
                lint.check_workflow('on: ' + value + '\njobs:\n  t:\n    runs-on: [self-hosted, studio]\n')

    def test_group_names_must_be_evaluated_expressions(self):
        for group in ('github.workflow-github.ref', '${{ github.workflow }}-github.ref'):
            with self.subTest(group=group):
                text = COMPLIANT.replace('${{ github.workflow }}-${{ github.ref }}', group)
                self.assertEqual(lint.check_workflow(text),
                                 ['concurrency group must include github.workflow and github.ref'])
        text = COMPLIANT.replace('${{ github.workflow }}-${{ github.ref }}',
                                 "ci-${{ github.workflow }}-${{ github.head_ref || github.ref }}")
        self.assertEqual(lint.check_workflow(text), [])

    def test_per_run_group_is_flagged(self):
        for extra in ('github.run_id', 'github.sha', 'github.run_number', 'github.run_attempt'):
            with self.subTest(extra=extra):
                text = COMPLIANT.replace('${{ github.ref }}', '${{ github.ref }}-${{ ' + extra + ' }}')
                problems = lint.check_workflow(text)
                self.assertEqual(len(problems), 1)
                self.assertIn('per-run value', problems[0])

    def test_reusable_workflow_from_another_owner_is_flagged(self):
        call = '  shared:\n    uses: {}\n'
        same = COMPLIANT + call.format('exampleowner/tools/.github/workflows/ci.yml@main')
        self.assertEqual(lint.check_workflow(same, 'ExampleOwner'), [])
        other = COMPLIANT + call.format('someone-else/actions/.github/workflows/ci.yml@v1')
        problems = lint.check_workflow(other, 'ExampleOwner')
        self.assertEqual(len(problems), 1)
        self.assertIn('outside this owner', problems[0])

    def test_byte_order_mark_and_ref_type_group(self):
        # The mark sits on the first key, so a reader that keeps it loses the on: triggers.
        text = 'on: [pull_request]\njobs:\n  t:\n    runs-on: [self-hosted, studio]\n'
        self.assertEqual(lint.check_workflow('\ufeff' + text),
                         ['runs on pull requests without the PR-only concurrency block'])
        self.assertEqual(lint.check_workflow(COMPLIANT.replace('github.ref }}', 'github.ref_type }}')),
                         ['concurrency group must include github.workflow and github.ref'])

    def test_non_pr_workflow_needs_only_the_studio_runner(self):
        text = COMPLIANT.replace('  pull_request:\n', '  workflow_dispatch:\n').replace(GOOD_CONCURRENCY, '')
        self.assertEqual(lint.check_workflow(text), [])

    def test_reusable_workflow_call_has_no_runner(self):
        text = COMPLIANT + '  shared:\n    uses: ./.github/workflows/shared.yml\n'
        self.assertEqual(lint.check_workflow(text), [])


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / 'Developer'
        self.cache = self.root / 'cache.json'
        self.gh_log = self.root / 'gh.log'
        self.visibility = {}
        self.remote = {}
        self.gh = self.root / 'fake-gh'
        self.gh.write_text(textwrap.dedent('''\
            #!/usr/bin/env python3
            import json, sys
            from pathlib import Path
            base = Path(sys.argv[0]).parent
            if sys.argv[1] == 'api':  # api repos/NAME/commits/main --jq .sha
                name = sys.argv[2].split('/', 1)[1].rsplit('/commits/', 1)[0]
                sha = json.loads((base / 'remote.json').read_text()).get(name)
                if sha is None:
                    print('HTTP 404: Not Found', file=sys.stderr)
                    raise SystemExit(1)
                print(sha)
                raise SystemExit(0)
            with (base / 'gh.log').open('a') as log:
                log.write(sys.argv[3] + '\\n')
            table = json.loads((base / 'visibility.json').read_text())
            name = sys.argv[3]
            if table.get(name) is None:
                print('HTTP 502: Bad Gateway', file=sys.stderr)
                raise SystemExit(1)
            print(json.dumps({'visibility': table[name], 'defaultBranchRef': {'name': 'main'}}))
            '''))
        self.gh.chmod(0o755)

    def repository(self, folder, name, visibility, files):
        path = self.home / folder
        path.mkdir(parents=True)
        run = lambda *args: subprocess.run(['git', '-C', str(path), *args], check=True, capture_output=True)
        run('init', '-q', '-b', 'main')
        for file, text in files.items():
            (path / '.github/workflows').mkdir(parents=True, exist_ok=True)
            (path / '.github/workflows' / file).write_text(text)
        (path / 'README').write_text(name)
        run('add', '.')
        run('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '-m', 'seed')
        run('remote', 'add', 'origin', 'https://github.com/' + name + '.git')
        run('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.visibility[name] = visibility
        self.remote[name] = subprocess.run(['git', '-C', str(path), 'rev-parse', 'HEAD'], check=True,
                                           capture_output=True, text=True).stdout.strip()
        return path

    def run_lint(self):
        (self.root / 'visibility.json').write_text(json.dumps(self.visibility))
        (self.root / 'remote.json').write_text(json.dumps(self.remote))
        return lint.lint(self.home, self.cache, str(self.gh), 'ExampleOwner')

    def test_reports_findings_per_file_and_skips_public_repositories(self):
        self.repository('Apps/Good', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        self.repository('Apps/Hosted', 'ExampleOwner/Hosted', 'PRIVATE',
                        {'ci.yml': COMPLIANT.replace('[self-hosted, studio]', 'macos-latest')})
        self.repository('Website/Open', 'ExampleOwner/Open', 'PUBLIC',
                        {'ci.yml': COMPLIANT.replace(GOOD_CONCURRENCY, '')})
        report = self.run_lint()
        self.assertEqual([(f['repository'], f['file']) for f in report['findings']],
                         [('ExampleOwner/Hosted', '.github/workflows/ci.yml')])
        self.assertEqual(report['exempt'], ['ExampleOwner/Open'])
        self.assertEqual(report['errors'], [])
        self.assertEqual(lint.exit_code(report), 1)

    def test_visibility_is_cached(self):
        self.repository('Apps/Good', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        self.repository('Apps/Good-worktree', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        for _ in range(2):
            report = self.run_lint()
            self.assertEqual(lint.exit_code(report), 0)
        self.assertEqual(self.gh_log.read_text().splitlines(), ['ExampleOwner/Good'])

    def test_gh_failure_skips_that_repository_and_is_not_cached(self):
        self.repository('Apps/Good', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        self.repository('Apps/Broken', 'ExampleOwner/Broken', None,
                        {'ci.yml': COMPLIANT.replace(GOOD_CONCURRENCY, '')})
        report = self.run_lint()
        self.assertEqual(report['findings'], [])
        self.assertEqual([e['repository'] for e in report['errors']], ['ExampleOwner/Broken'])
        self.assertIn('HTTP 502', report['errors'][0]['problem'])
        self.assertEqual(lint.exit_code(report), 2)
        self.assertNotIn('exampleowner/broken', json.loads(self.cache.read_text()))

    def test_git_failure_is_an_error_not_a_clean_run(self):
        path = self.repository('Apps/Good', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        (path / '.git/config').write_text('[broken\n')
        report = self.run_lint()
        self.assertEqual(report['checked'], [])
        self.assertEqual(len(report['errors']), 1)
        self.assertIn('cannot read origin', report['errors'][0]['problem'])
        self.assertEqual(lint.exit_code(report), 2)

    def test_checkout_without_origin_is_not_an_error(self):
        path = self.repository('Apps/Good', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        subprocess.run(['git', '-C', str(path), 'remote', 'remove', 'origin'], check=True)
        report = self.run_lint()
        self.assertEqual((report['checked'], report['errors']), ([], []))

    def test_stale_or_unverifiable_local_refs_are_reported(self):
        self.repository('Apps/Old', 'ExampleOwner/Old', 'PRIVATE', {'ci.yml': COMPLIANT})
        self.repository('Apps/Offline', 'ExampleOwner/Offline', 'PRIVATE', {'ci.yml': COMPLIANT})
        self.remote['ExampleOwner/Old'] = 'f' * 40
        del self.remote['ExampleOwner/Offline']
        report = self.run_lint()
        stale = {entry['repository']: entry['problem'] for entry in report['stale']}
        self.assertRegex(report['checked'][0]['committed'], r'^\d{4}-\d{2}-\d{2}$')
        self.assertIn('differs from GitHub ffffffffffff', stale['ExampleOwner/Old'])
        self.assertIn('freshness unknown', stale['ExampleOwner/Offline'])
        self.assertEqual(lint.exit_code(report), 0)  # Stale results are still results.

    def test_workflow_with_byte_order_mark_is_read_from_git(self):
        self.repository('Apps/Bom', 'ExampleOwner/Bom', 'PRIVATE',
                        {'ci.yml': '\ufeffon: [pull_request]\njobs:\n  t:\n    runs-on: [self-hosted, studio]\n'})
        report = self.run_lint()
        self.assertEqual([f['problem'] for f in report['findings']],
                         ['runs on pull requests without the PR-only concurrency block'])

    def test_missing_root_and_missing_gh_are_reported(self):
        report = lint.lint(self.root / 'absent', self.cache, str(self.gh), 'ExampleOwner')
        self.assertEqual(lint.exit_code(report), 2)
        self.repository('Apps/Good', 'ExampleOwner/Good', 'PRIVATE', {'ci.yml': COMPLIANT})
        report = lint.lint(self.home, self.cache, str(self.root / 'no-gh'), 'ExampleOwner')
        self.assertEqual([e['repository'] for e in report['errors']], ['ExampleOwner/Good'])

    def test_command_line_text_and_json(self):
        self.repository('Apps/Hosted', 'ExampleOwner/Hosted', 'PRIVATE',
                        {'ci.yml': COMPLIANT.replace(GOOD_CONCURRENCY, '')})
        (self.root / 'visibility.json').write_text(json.dumps(self.visibility))
        (self.root / 'remote.json').write_text(json.dumps(self.remote))
        base = [sys.executable, '-B', str(TOOLS / 'ci-lint.py'), '--root', str(self.home),
                '--cache', str(self.cache), '--gh', str(self.gh), '--owner', 'ExampleOwner']
        text = subprocess.run(base, capture_output=True, text=True)
        self.assertEqual(text.returncode, 1)
        self.assertEqual(text.stdout, 'ExampleOwner/Hosted .github/workflows/ci.yml: '
                                      'runs on pull requests without the PR-only concurrency block\n')
        data = subprocess.run(base + ['--json'], capture_output=True, text=True)
        self.assertEqual(data.returncode, 1)
        self.assertEqual(len(json.loads(data.stdout)['findings']), 1)


class SyncHookTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'source'
        (self.source / 'tools').mkdir(parents=True)
        (self.root / 'repos').mkdir()
        self.config = {'source': str(self.source), 'ci_lint_root': str(self.root / 'repos')}

    def test_reports_findings_without_touching_the_source_checkout(self):
        (self.source / 'tools/ci-lint.py').write_text(
            'import json\nprint(json.dumps({"findings": [{"repository": "o/r", "file": "w.yml", '
            '"problem": "bad"}], "errors": [], "checked": [{"repository": "o/r", '
            '"revision": "0123456789abcdef"}]}))\nraise SystemExit(1)\n')
        result = sync.lint_ci(self.config, self.root)
        self.assertEqual(result, {'status': 'findings', 'checked': ['o/r@0123456789ab'],
                                  'findings': ['o/r w.yml: bad']})
        (self.source / 'tools/ci-lint.py').write_text(
            'import json\nprint(json.dumps({"findings": [], "errors": [], "checked": [], '
            '"stale": [{"repository": "o/r", "problem": "old"}]}))\n')
        self.assertEqual(sync.lint_ci(self.config, self.root),
                         {'status': 'clean', 'checked': [], 'stale': ['o/r: old']})
        self.assertEqual(sorted(p.name for p in (self.source / 'tools').iterdir()), ['ci-lint.py'])

    def test_crash_old_source_or_missing_root_never_raises(self):
        self.assertEqual(sync.lint_ci(self.config, self.root)['status'], 'skipped')
        for body in ('raise RuntimeError("boom")\n',
                     'print(\'{"findings": [], "errors": [], "checked": [{"repository": "o/r"}]}\')\n'):
            (self.source / 'tools/ci-lint.py').write_text(body)
            self.assertEqual(sync.lint_ci(self.config, self.root)['status'], 'error')
        self.assertEqual(sync.lint_ci(dict(self.config, ci_lint_root=str(self.root / 'none')), self.root)['status'],
                         'skipped')
        self.assertEqual(sync.lint_ci({'source': 7}, self.root)['status'], 'error')

    def test_findings_do_not_change_the_update_result(self):
        config_path = self.root / 'config.json'
        config_path.write_text(json.dumps(dict(self.config, brain=str(self.root), harnesses=[])))
        current = {'status': 'current', 'revision': 'a' * 40}
        with patch.object(sys, 'argv', ['sync', '--config', str(config_path)]), \
                patch.object(sync, 'sync_brain', return_value=current), \
                patch.object(sync, 'sync_source', return_value=current), \
                patch.object(sync, 'lint_ci', return_value={'status': 'findings', 'findings': ['x']}) as hook:
            self.assertEqual(sync.main(), 0)
        hook.assert_called_once()
        self.assertEqual(json.loads((self.root / 'status.json').read_text())['ci_lint']['status'], 'findings')

    def test_blocked_source_skips_the_lint(self):
        config_path = self.root / 'config.json'
        config_path.write_text(json.dumps(dict(self.config, brain=str(self.root), harnesses=[])))
        with patch.object(sys, 'argv', ['sync', '--config', str(config_path)]), \
                patch.object(sync, 'sync_brain', return_value={'status': 'current', 'revision': 'a' * 40}), \
                patch.object(sync, 'sync_source', side_effect=sync.Blocked('changed')), \
                patch.object(sync, 'lint_ci') as hook:
            self.assertEqual(sync.main(), 1)
        hook.assert_not_called()


if __name__ == '__main__':
    unittest.main()
