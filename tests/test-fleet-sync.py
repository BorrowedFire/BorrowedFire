#!/usr/bin/env python3
"""Protect memory edits and prevent unreviewed or divergent software installation."""
import importlib.util
import json
from pathlib import Path
import subprocess
import shutil
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sync', Path(__file__).resolve().parents[1] / 'tools/sync-fleet.py')
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

class SyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.remote = self.root / 'remote.git'
        self.seed = self.root / 'seed'
        self.clone = self.root / 'clone'
        self.command('git', 'init', '--bare', str(self.remote))
        self.command('git', 'init', '-b', 'main', str(self.seed))
        self.git(self.seed, 'config', 'user.email', 'fixture@example.invalid')
        self.git(self.seed, 'config', 'user.name', 'Fixture')
        (self.seed / 'file').write_text('first')
        (self.seed / 'doctrine').mkdir()
        (self.seed / 'doctrine/DOCTRINE.md').write_text('<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nold doctrine\n<!-- END BORROWEDFIRE DOCTRINE -->\n')
        (self.seed / 'skills/demo').mkdir(parents=True)
        (self.seed / 'skills/demo/SKILL.md').write_text('old skill\n')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'first')
        self.first = self.git(self.seed, 'rev-parse', 'HEAD')
        self.git(self.seed, 'remote', 'add', 'origin', str(self.remote))
        self.git(self.seed, 'push', 'origin', 'main')
        self.command('git', 'clone', '-b', 'main', str(self.remote), str(self.clone))
        self.git(self.clone, 'config', 'user.email', 'fixture@example.invalid')
        self.git(self.clone, 'config', 'user.name', 'Fixture')
        self.brain = self.root / 'brain'
        (self.brain / 'notes').mkdir(parents=True)
        self.git(self.brain, 'init', '-b', 'main')
        self.git(self.brain, 'config', 'user.email', 'fixture@example.invalid')
        self.git(self.brain, 'config', 'user.name', 'Fixture')
        self.config = {'source': str(self.clone), 'harnesses': []}
        discovery = patch.object(sync, 'discovered_harnesses', side_effect=lambda config: config['harnesses'])
        discovery.start()
        self.addCleanup(discovery.stop)

    def command(self, *args):
        return subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True).strip()

    def git(self, repo, *args):
        return self.command('git', '-C', str(repo), *args)

    def advance(self):
        (self.seed / 'file').write_text('second')
        self.git(self.seed, 'commit', '-am', 'second')
        self.git(self.seed, 'push', 'origin', 'main')
        return self.git(self.seed, 'rev-parse', 'HEAD')

    def record(self, sha, status='approved'):
        (self.brain / 'notes/borrowedfire-release-channel.md').write_text(
            '---\nrelease_commit: '+sha+'\nrelease_status: '+status+
            '\nreview_url: https://github.com/BorrowedFire/BorrowedFire/pull/99\n---\n')
        self.git(self.brain, 'add', 'notes/borrowedfire-release-channel.md')
        self.git(self.brain, 'commit', '--allow-empty', '-m', 'release record')

    def private_fixture(self):
        context = self.root / 'installed/AGENTS.md'
        context.parent.mkdir()
        skills = context.parent / 'skills'
        shutil.copytree(self.clone / 'skills', skills)
        (skills / 'demo/.borrowedfire-copy').touch()
        (skills / '.borrowedfire-manifest').write_text('demo copy\n')
        alias = context.parent / 'CLAUDE.md'
        alias.symlink_to('AGENTS.md')
        self.config['harnesses'] = [{'context': str(p), 'skills': str(skills)} for p in (context, alias)]
        self.config['private_context'] = 'config/agent-instructions.md'
        (self.seed / 'tools').mkdir()
        (self.seed / 'tools/skill-lint.sh').write_text('exit 0\n')
        # The real installer's atomic symlink behavior is exercised by test-install.sh.
        (self.seed / 'install.sh').write_text(
            'set -eu\nprivate=""\nwhile [ "$#" -gt 0 ]; do\n'
            'case "$1" in --context-file) private="$2"; shift;; esac\nshift\ndone\n'
            'test -n "$private"\ncp "$private" "' + str(context) + '"\n'
            'printf "installed\\n" >> "' + str(context.parent / 'installs') + '"\n')
        self.git(self.seed, 'add', 'tools', 'install.sh')
        self.git(self.seed, 'commit', '-m', 'context-aware fixture installer')
        self.git(self.seed, 'push', 'origin', 'main')
        self.git(self.clone, 'pull', '--ff-only')
        self.target = self.git(self.clone, 'rev-parse', 'HEAD')
        self.record(self.target)
        initial = self.private_record('first')
        context.write_text(initial)
        return context, alias, initial

    def private_record(self, label):
        path = self.brain / 'config/agent-instructions.md'
        path.parent.mkdir(exist_ok=True)
        body = ('# Private host instructions\nOwner context ' + label + '\n'
                '<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nPrivate rules ' + label + '\n'
                '<!-- END BORROWEDFIRE DOCTRINE -->\nLocal access notes ' + label + '\n')
        path.write_text('---\ntype: note\n---\n' + body)
        self.git(self.brain, 'add', 'config/agent-instructions.md')
        self.git(self.brain, 'commit', '-m', 'private instructions ' + label)
        return body

    def test_private_update_with_unchanged_release_and_missing_receipt(self):
        context, alias, _ = self.private_fixture()
        current = self.private_record('second')
        result = sync.sync_source(self.config, self.brain, {'status': 'current', 'revision': self.target})
        self.assertEqual(context.read_text(), current)
        self.assertTrue(alias.is_symlink())
        self.assertEqual(alias.read_text(), current)
        sync.sync_source(self.config, self.brain, result)
        self.assertEqual((context.parent / 'installs').read_text(), 'installed\n')
        sync.sync_source(self.config, self.brain, {})
        self.assertEqual((context.parent / 'installs').read_text(), 'installed\ninstalled\n')
        self.assertEqual(self.git(self.brain, 'status', '--porcelain'), '')
        self.assertEqual(self.git(self.clone, 'status', '--porcelain', '--ignored'), '')

    def test_private_local_edits_and_unrelated_committed_text_are_preserved(self):
        context, _, initial = self.private_fixture()
        self.private_record('second')
        unrelated = self.brain / 'config/unrelated.md'
        unrelated.write_text(initial.replace('first', 'not the enrolled source'))
        self.git(self.brain, 'add', 'config/unrelated.md')
        self.git(self.brain, 'commit', '-m', 'unrelated instructions')
        for changed in (initial + 'local change\n', initial.replace('\n', '\r\n'), unrelated.read_text()):
            with self.subTest(changed=changed[:25]):
                context.write_bytes(changed.encode())
                with self.assertRaisesRegex(sync.Blocked, 'private context has local changes'):
                    sync.sync_source(self.config, self.brain, {'status': 'current', 'revision': self.target})
                self.assertEqual(context.read_bytes(), changed.encode())
                self.assertFalse((context.parent / 'installs').exists())
                self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.target)

    def test_private_context_rejects_uncommitted_content_and_unsafe_paths(self):
        _, _, _ = self.private_fixture()
        path = self.brain / self.config['private_context']
        original = path.read_text()
        path.write_text(original + 'uncommitted\n')
        with self.assertRaisesRegex(sync.Blocked, 'differs from the synchronized commit'):
            sync.sync_source(self.config, self.brain, {})
        path.write_text(original)
        for bad in ('../outside.md', str(path), 'config/../outside.md'):
            with self.subTest(path=bad):
                self.config['private_context'] = bad
                with self.assertRaisesRegex(sync.Blocked, 'under brain config'):
                    sync.sync_source(self.config, self.brain, {})
        self.config['private_context'] = 'config/alias.md'
        (self.brain / 'config/alias.md').symlink_to(path)
        with self.assertRaisesRegex(sync.Blocked, 'must not use symlinks'):
            sync.sync_source(self.config, self.brain, {})

    def test_source_release_does_not_replace_private_context_with_public_doctrine(self):
        context, alias, initial = self.private_fixture()
        (self.seed / 'doctrine/DOCTRINE.md').write_text(
            '<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nnew public rules\n<!-- END BORROWEDFIRE DOCTRINE -->\n')
        self.git(self.seed, 'commit', '-am', 'public doctrine update')
        self.git(self.seed, 'push', 'origin', 'main')
        target = self.git(self.seed, 'rev-parse', 'HEAD')
        self.record(target)
        result = sync.sync_source(self.config, self.brain, {})
        self.assertEqual(result['revision'], target)
        self.assertEqual(context.read_text(), initial)
        self.assertEqual(alias.read_text(), initial)

    def test_private_targets_preserve_other_harnesses_and_reject_mixed_aliases(self):
        context, alias, initial = self.private_fixture()
        separate = context.parent / 'separate/AGENTS.md'
        separate.parent.mkdir()
        public = 'Separate owner instructions\n' + (self.clone / 'doctrine/DOCTRINE.md').read_text()
        separate.write_text(public)
        self.config['harnesses'].append({'context': str(separate), 'skills': str(context.parent / 'skills')})
        self.config['private_context_targets'] = [str(context), str(alias)]
        result = sync.sync_source(self.config, self.brain, {'status': 'current', 'revision': self.target})
        self.assertEqual(result['status'], 'current')
        self.assertEqual(context.read_text(), initial)
        self.assertEqual(separate.read_text(), public)
        self.config['private_context_targets'] = [str(context)]
        with self.assertRaisesRegex(sync.Blocked, 'cannot mix public and private'):
            sync.sync_source(self.config, self.brain, result)
        self.config['private_context_targets'] = [str(context.parent / 'unknown.md')]
        with self.assertRaisesRegex(sync.Blocked, 'must be enrolled'):
            sync.sync_source(self.config, self.brain, result)

    def test_current_receipt_cannot_hide_installed_integrity_drift(self):
        for mutation in ('duplicate_doctrine', 'missing_marker', 'missing_manifest_entry',
                         'executable_mode', 'symlink_same_bytes', 'extra_directory',
                         'surplus_owned_copy', 'surplus_owned_link'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory(dir=self.root) as directory:
                installed = Path(directory)
                context = installed / 'AGENTS.md'
                doctrine = (self.clone / 'doctrine/DOCTRINE.md').read_text()
                context.write_text('Owner text before.\n' + doctrine + 'Owner text after.\n')
                skills = installed / 'skills'
                shutil.copytree(self.clone / 'skills', skills)
                marker = skills / 'demo/.borrowedfire-copy'
                marker.touch()
                manifest = skills / '.borrowedfire-manifest'
                manifest.write_text('demo copy\n')
                # Unowned skills remain outside the updater's managed set.
                (skills / 'unrelated').mkdir()
                (skills / 'unrelated/SKILL.md').write_text('owner skill\n')
                self.config['harnesses'] = [{'context': str(context), 'skills': str(skills)}]
                self.record(self.first)
                prior = {'revision': self.first, 'status': 'current'}
                self.assertEqual(sync.sync_source(self.config, self.brain, prior)['status'], 'current')
                file = skills / 'demo/SKILL.md'
                if mutation == 'duplicate_doctrine':
                    context.write_text(context.read_text() + doctrine.replace('old doctrine', 'stale doctrine'))
                elif mutation == 'missing_marker':
                    marker.unlink()
                elif mutation == 'missing_manifest_entry':
                    manifest.write_text('')
                elif mutation == 'executable_mode':
                    file.chmod(0o755)
                elif mutation == 'symlink_same_bytes':
                    external = installed / 'external.md'
                    external.write_bytes(file.read_bytes())
                    file.unlink()
                    file.symlink_to(external)
                elif mutation.startswith('surplus_owned_'):
                    mode = mutation.removeprefix('surplus_owned_')
                    manifest.write_text('demo copy\nremoved ' + mode + '\n')
                    if mode == 'copy':
                        shutil.copytree(skills / 'demo', skills / 'removed')
                    else:
                        (skills / 'removed').symlink_to(self.clone / 'skills/demo')
                else:
                    (skills / 'demo/owner-extra').mkdir()
                with self.assertRaises(sync.Blocked):
                    sync.sync_source(self.config, self.brain, prior)

    def test_new_harness_blocks_before_source_changes(self):
        self.record(self.advance())
        with patch.object(sync, 'discovered_harnesses', return_value=[{'skills':'new', 'context':'new'}]):
            with self.assertRaisesRegex(sync.Blocked, 'harness set changed'):
                sync.sync_source(self.config, self.brain, {})
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.first)

    def test_hidden_source_changes_cannot_reuse_current_receipt(self):
        # Linked installs must match Git objects, not the same altered source directory.
        self.record(self.first)
        prior = {'revision': self.first, 'status': 'current'}
        for flag in ('assume-unchanged', 'skip-worktree'):
            with self.subTest(flag=flag):
                self.git(self.clone, 'update-index', '--' + flag, 'skills/demo/SKILL.md')
                (self.clone / 'skills/demo/SKILL.md').write_text('hidden edit')
                self.assertEqual(self.git(self.clone, 'status', '--porcelain'), '')
                with self.assertRaisesRegex(sync.Blocked, 'hidden index flags'):
                    sync.sync_source(self.config, self.brain, prior)
                (self.clone / 'skills/demo/SKILL.md').write_text('old skill\n')
                self.git(self.clone, 'update-index', '--no-' + flag, 'skills/demo/SKILL.md')
        (self.clone / '.git/info/exclude').write_text('.env\n')
        ignored = self.clone / 'skills/demo/.env'
        ignored.write_text('private local content')
        self.assertEqual(self.git(self.clone, 'status', '--porcelain'), '')
        with self.assertRaisesRegex(sync.Blocked, 'Source entries differ'):
            sync.sync_source(self.config, self.brain, prior)
        self.assertEqual(ignored.read_text(), 'private local content')
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.first)

    def test_source_bytes_and_modes_do_not_depend_on_git_status(self):
        sync.verify_source(self.clone, self.first)
        path = self.clone / 'skills/demo/SKILL.md'
        for change in ('bytes', 'mode', 'link', 'directory'):
            with self.subTest(change=change):
                if change == 'bytes':
                    path.write_text('different')
                elif change == 'mode':
                    path.chmod(0o755)
                elif change == 'link':
                    path.unlink()
                    path.symlink_to(self.seed / 'skills/demo/SKILL.md')
                else:
                    (self.clone / 'skills/demo/extra').mkdir()
                with self.assertRaisesRegex(sync.Blocked, 'Source entries differ'):
                    sync.verify_source(self.clone, self.first)
                if path.is_symlink():
                    path.unlink()
                path.write_text('old skill\n')
                path.chmod(0o644)

    def test_partial_install_with_existing_harness_stops_for_reconciliation(self):
        context = self.root / 'installed/AGENTS.md'
        skills = self.root / 'installed/skills'
        context.parent.mkdir()
        context.write_text('<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nold doctrine\n<!-- END BORROWEDFIRE DOCTRINE -->\n')
        (skills / 'demo').mkdir(parents=True)
        (skills / 'demo/SKILL.md').write_text('old skill\n')
        (skills / 'demo/.borrowedfire-copy').touch()
        (skills / '.borrowedfire-manifest').write_text('demo copy\n')
        self.config['harnesses'] = [{'context': str(context), 'skills': str(skills)}]
        (self.seed / 'tools').mkdir()
        (self.seed / 'tools/skill-lint.sh').write_text('exit 0\n')
        (self.seed / 'doctrine/DOCTRINE.md').write_text('<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nnew doctrine\n<!-- END BORROWEDFIRE DOCTRINE -->\n')
        (self.seed / 'install.sh').write_text('exit 7\n')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'new release')
        self.git(self.seed, 'push', 'origin', 'main')
        self.record(self.git(self.seed, 'rev-parse', 'HEAD'))
        with self.assertRaisesRegex(sync.Blocked, 'exit 7'):
            sync.sync_source(self.config, self.brain, {})
        with self.assertRaisesRegex(sync.Blocked, 'doctrine differs'):
            sync.sync_source(self.config, self.brain, {})
        self.assertEqual(context.read_text(), '<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nold doctrine\n<!-- END BORROWEDFIRE DOCTRINE -->\n')

    def test_memory_fast_forwards_and_second_run_is_current(self):
        target = self.advance()
        for _ in range(2):
            self.assertEqual(sync.sync_brain(self.clone)['revision'], target)

    def test_memory_dirty_and_untracked_files_stay_untouched(self):
        self.advance()
        (self.clone / 'owner-draft').write_text('keep')
        with self.assertRaisesRegex(sync.Blocked, 'local changes'):
            sync.sync_brain(self.clone)
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.first)
        self.assertEqual((self.clone / 'owner-draft').read_text(), 'keep')

    def test_unpushed_memory_is_never_reset_or_pushed(self):
        (self.clone / 'file').write_text('local')
        self.git(self.clone, 'commit', '-am', 'local')
        local = self.git(self.clone, 'rev-parse', 'HEAD')
        with self.assertRaisesRegex(sync.Blocked, 'unpushed or divergent'):
            sync.sync_brain(self.clone)
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), local)
        self.assertEqual(self.git(self.seed, 'rev-parse', 'HEAD'), self.first)

    def test_in_progress_operation_blocks_memory(self):
        (self.clone / '.git/MERGE_HEAD').write_text(self.first)
        with self.assertRaisesRegex(sync.Blocked, 'in progress'):
            sync.sync_brain(self.clone)

    def test_active_bisect_blocks_source_without_changing_operation(self):
        # A clean detached bisect commit used to advance to the approved revision.
        self.advance()
        (self.seed / 'file').write_text('third')
        self.git(self.seed, 'commit', '-am', 'third')
        self.git(self.seed, 'push', 'origin', 'main')
        target = self.git(self.seed, 'rev-parse', 'HEAD')
        self.git(self.clone, 'fetch', 'origin', 'main')
        self.git(self.clone, 'merge', '--ff-only', target)
        self.git(self.clone, 'bisect', 'start', target, self.first)
        before = self.git(self.clone, 'rev-parse', 'HEAD')
        log = (self.clone / '.git/BISECT_LOG').read_bytes()
        self.record(target)
        self.assertNotEqual(before, target)
        self.assertEqual(self.git(self.clone, 'status', '--porcelain'), '')
        with self.assertRaisesRegex(sync.Blocked, 'in progress'):
            sync.sync_source(self.config, self.brain, {})
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), before)
        self.assertEqual((self.clone / '.git/BISECT_LOG').read_bytes(), log)

    def test_new_unapproved_main_does_not_install(self):
        latest = self.advance()
        self.record(self.first)
        prior = {'revision': self.first, 'status': 'current'}
        with patch.object(sync, 'verify_install') as verify:
            result = sync.sync_source(self.config, self.brain, prior)
        verify.assert_called_once()
        self.assertTrue(result['awaiting_review'])
        self.assertEqual(result['upstream_revision'], latest)
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.first)

    def test_source_divergence_blocks_without_overwriting(self):
        target = self.advance()
        (self.clone / 'file').write_text('local improvement')
        self.git(self.clone, 'commit', '-am', 'local improvement')
        self.record(target)
        with self.assertRaisesRegex(sync.Blocked, 'reconciliation required'):
            sync.sync_source(self.config, self.brain, {})
        self.assertEqual((self.clone / 'file').read_text(), 'local improvement')

    def test_non_main_source_positions_are_preserved(self):
        self.record(self.advance())
        for args in (('-b', 'maintenance'), ('--detach', self.first)):
            with self.subTest(args=args):
                self.git(self.clone, 'checkout', *args)
                with self.assertRaisesRegex(sync.Blocked, 'Source is not on main'):
                    sync.sync_source(self.config, self.brain, {})
                self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.first)
        self.assertEqual(self.git(self.clone, 'rev-parse', 'maintenance'), self.first)

    def test_release_authority_must_be_the_synchronized_committed_record(self):
        self.record(self.first)
        revision = self.git(self.brain, 'rev-parse', 'HEAD')
        self.assertEqual(sync.release_record(self.brain, revision), self.first)
        record = self.brain / 'notes/borrowedfire-release-channel.md'
        committed = record.read_text()
        record.write_text(committed + '\nlocal edit\n')
        with self.assertRaisesRegex(sync.Blocked, 'differs from the synchronized commit'):
            sync.release_record(self.brain, revision)
        record.write_text(committed)
        self.git(self.brain, 'rm', '--cached', 'notes/borrowedfire-release-channel.md')
        self.git(self.brain, 'commit', '-m', 'remove published approval')
        (self.brain / '.git/info/exclude').write_text('notes/borrowedfire-release-channel.md\n')
        self.assertEqual(self.git(self.brain, 'status', '--porcelain'), '')
        with self.assertRaises(sync.Blocked):
            sync.release_record(self.brain)
        with self.assertRaisesRegex(sync.Blocked, 'Brain changed'):
            sync.release_record(self.brain, revision)

    def test_pending_record_cannot_authorize_install(self):
        self.record(self.advance(), 'pending')
        with self.assertRaisesRegex(sync.Blocked, 'No approved'):
            sync.sync_source(self.config, self.brain, {})
        self.assertEqual(self.git(self.clone, 'rev-parse', 'HEAD'), self.first)

    def test_unpublished_revision_cannot_authorize_install(self):
        self.record('f' * 40)
        with self.assertRaisesRegex(sync.Blocked, 'not in published main'):
            sync.sync_source(self.config, self.brain, {})

    def test_approved_install_then_repeat_checks_actual_files(self):
        # The fixture installer represents the same installer command used on each host.
        (self.seed / 'tools').mkdir()
        (self.seed / 'tools/skill-lint.sh').write_text('exit 0\n')
        (self.seed / 'doctrine/DOCTRINE.md').write_text('<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nreviewed doctrine\n<!-- END BORROWEDFIRE DOCTRINE -->\n')
        (self.seed / 'skills/demo/SKILL.md').write_text('reviewed skill\n')
        context = self.root / 'installed/AGENTS.md'
        skills = self.root / 'installed/skills'
        context.parent.mkdir()
        context.write_text('<!-- BEGIN BORROWEDFIRE DOCTRINE -->\nold doctrine\n<!-- END BORROWEDFIRE DOCTRINE -->\n')
        (skills / 'demo').mkdir(parents=True)
        (skills / 'demo/SKILL.md').write_text('old skill\n')
        (skills / 'demo/.borrowedfire-copy').touch()
        (skills / '.borrowedfire-manifest').write_text('demo copy\n')
        # Paths come only from the test's temporary directory.
        (self.seed / 'install.sh').write_text(
            'set -e\nmkdir -p "'+str(skills)+'"\ncp doctrine/DOCTRINE.md "'+str(context)+
            '"\ncp -R skills/demo "'+str(skills)+'"\nprintf "installed\\n" >> "'+str(context.parent/'installs')+'"\n')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'reviewed installer')
        self.git(self.seed, 'push', 'origin', 'main')
        target = self.git(self.seed, 'rev-parse', 'HEAD')
        self.record(target)
        self.config['harnesses'] = [{'context': str(context), 'skills': str(skills)}]
        result = sync.sync_source(self.config, self.brain, {})
        self.assertEqual(result['revision'], target)
        sync.sync_source(self.config, self.brain, result)
        config_path = self.root / 'config.json'
        config_path.write_text(json.dumps(dict(self.config, brain=str(self.brain))))
        for index, receipt in enumerate(('{', '[]', '{"borrowedfire": []}'), start=2):
            with self.subTest(receipt=receipt):
                (self.root / 'status.json').write_text(receipt)
                with patch.object(sys, 'argv', ['sync', '--config', str(config_path)]), patch.object(
                        sync, 'sync_brain', return_value={'status': 'current', 'revision': self.git(self.brain, 'rev-parse', 'HEAD')}):
                    self.assertEqual(sync.main(), 0)
                self.assertEqual(len((context.parent/'installs').read_text().splitlines()), index)
                self.assertEqual(json.loads((self.root/'status.json').read_text())['borrowedfire']['status'], 'current')
        (skills / 'demo/SKILL.md').write_text('owner edit')
        with self.assertRaisesRegex(sync.Blocked, 'differ'):
            sync.sync_source(self.config, self.brain, result)
        self.assertEqual((skills / 'demo/SKILL.md').read_text(), 'owner edit')

    def test_failed_install_does_not_return_success_and_is_retryable(self):
        (self.seed / 'tools').mkdir()
        (self.seed / 'tools/skill-lint.sh').write_text('exit 0\n')
        (self.seed / 'install.sh').write_text('exit 7\n')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'installer')
        self.git(self.seed, 'push', 'origin', 'main')
        self.record(self.git(self.seed, 'rev-parse', 'HEAD'))
        for _ in range(2):
            with self.assertRaisesRegex(sync.Blocked, 'exit 7'):
                sync.sync_source(self.config, self.brain, {})

class CommandTests(unittest.TestCase):
    def test_interruptions_stop_descendant_writes(self):
        # A detached child group used to survive updater SIGTERM or KeyboardInterrupt.
        for signum in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signum=signum), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                ready, written = root / 'ready', root / 'orphan-write'
                child = ('from pathlib import Path; import time; '
                         'Path(' + repr(str(ready)) + ').touch(); time.sleep(1); '
                         'Path(' + repr(str(written)) + ').touch(); time.sleep(10)')
                leader = ('import subprocess,sys; '
                          'subprocess.Popen([sys.executable,"-c",' + repr(child) + ']); '
                          'import time; time.sleep(20)')
                wrapper = ('import importlib.util,sys; '
                           's=importlib.util.spec_from_file_location("sync",' + repr(str(Path(sync.__file__))) + '); '
                           'm=importlib.util.module_from_spec(s); s.loader.exec_module(m); '
                           'm.run([sys.executable,"-c",' + repr(leader) + '])')
                proc = subprocess.Popen([sys.executable, '-B', '-c', wrapper],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    deadline = time.monotonic() + 5
                    while not ready.exists() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(ready.exists())
                    proc.send_signal(signum)
                    proc.wait(timeout=5)
                    self.assertNotEqual(proc.returncode, 0)
                    time.sleep(1.1)
                    self.assertFalse(written.exists())
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()

if __name__ == '__main__':
    unittest.main()
