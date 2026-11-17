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
        self.gh = self.root / 'fake-gh'
        self.gh.write_text(textwrap.dedent('''\
            #!/usr/bin/env python3
            import json, sys
            from pathlib import Path
            base = Path(sys.argv[0]).parent
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
        return path

    def run_lint(self):
        (self.root / 'visibility.json').write_text(json.dumps(self.visibility))
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
            '"problem": "bad"}], "errors": [], "checked": [1]}))\nraise SystemExit(1)\n')
        result = sync.lint_ci(self.config, self.root)
        self.assertEqual(result, {'status': 'findings', 'checked': 1, 'findings': ['o/r w.yml: bad']})
        self.assertEqual(sorted(p.name for p in (self.source / 'tools').iterdir()), ['ci-lint.py'])

    def test_crash_old_source_or_missing_root_never_raises(self):
        self.assertEqual(sync.lint_ci(self.config, self.root)['status'], 'skipped')
        (self.source / 'tools/ci-lint.py').write_text('raise RuntimeError("boom")\n')
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
