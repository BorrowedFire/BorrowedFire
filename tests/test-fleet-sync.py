#!/usr/bin/env python3
"""Protect memory edits and prevent unreviewed or divergent software installation."""
import importlib.util
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
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

    def test_current_receipt_cannot_hide_installed_integrity_drift(self):
        for mutation in ('duplicate_doctrine', 'missing_marker', 'missing_manifest_entry',
                         'executable_mode', 'symlink_same_bytes', 'extra_directory'):
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
            '"\ncp -R skills/demo "'+str(skills)+'"\n')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'reviewed installer')
        self.git(self.seed, 'push', 'origin', 'main')
        target = self.git(self.seed, 'rev-parse', 'HEAD')
        self.record(target)
        self.config['harnesses'] = [{'context': str(context), 'skills': str(skills)}]
        result = sync.sync_source(self.config, self.brain, {})
        self.assertEqual(result['revision'], target)
        sync.sync_source(self.config, self.brain, result)
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

if __name__ == '__main__':
    unittest.main()
