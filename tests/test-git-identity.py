#!/usr/bin/env python3
"""Exercise real Git commands: unsafe identities must fail before creating a commit.

The existing updater suite covers source authorization, but did not exercise Git
identity precedence, hook composition, or plumbing-produced outgoing metadata.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[1] / 'tools/git-identity.py'
spec = importlib.util.spec_from_file_location('identity', SOURCE)
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)
sync_spec = importlib.util.spec_from_file_location('sync', SOURCE.with_name('sync-fleet.py'))
sync = importlib.util.module_from_spec(sync_spec)
sync_spec.loader.exec_module(sync)


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='git-identity-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / 'home'
        self.home.mkdir()
        clean_env = {key: value for key, value in os.environ.items()
                     if not key.startswith('GIT_') and key not in ('EMAIL', 'HOME', 'XDG_CONFIG_HOME')}
        clean_env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'),
                         GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0')
        env = patch.dict(os.environ, clean_env, clear=True)
        env.start()
        self.addCleanup(env.stop)
        self.repo = self.root / 'repo'
        self.command('git', 'init', '-b', 'main', str(self.repo))
        old_cwd = Path.cwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, old_cwd)
        self.git('config', '--global', 'user.name', 'Example Owner')
        self.git('config', '--global', 'user.email', 'private@example.invalid')
        self.git('remote', 'add', 'origin', 'https://github.com/ExampleOwner/project.git')
        self.state = self.home / 'identity'
        self.policy = {'version': 1, 'github_login': 'ExampleOwner', 'github_id': 1234,
                       'email': '1234+ExampleOwner@users.noreply.github.com',
                       'allowed_author_emails': []}
        self.install()

    def command(self, *args, ok=True, env=None, data=None):
        result = subprocess.run(args, text=True, input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=env)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def git(self, *args, **kwargs):
        return self.command('git', '-C', str(self.repo), *args, **kwargs)

    def install(self, previous=()):
        return identity.install(self.policy, previous, self.state, SOURCE, sys.executable)

    def commit(self, *args, **kwargs):
        return self.git('commit', '--allow-empty', '-m', 'fixture', *args, **kwargs)

    def hook(self, name, text):
        path = self.repo / '.git/hooks' / name
        path.write_text('#!/bin/sh\n' + text + '\n')
        path.chmod(0o700)
        return path

    def cli(self, command, *args, **kwargs):
        return self.command(sys.executable, '-B', str(SOURCE), command, '--state', str(self.state), *args, **kwargs)

    def test_scoped_config_and_normal_commit(self):
        self.assertEqual(self.git('config', 'user.email').stdout.strip(), self.policy['email'])
        self.cli('doctor')
        self.commit()
        self.assertEqual(self.git('show', '-s', '--format=%ae%n%ce').stdout.splitlines(),
                         [self.policy['email']] * 2)

    def test_unrelated_identity_is_unchanged(self):
        self.git('remote', 'set-url', 'origin', 'https://github.com/OtherOwner/project.git')
        self.assertEqual(self.git('config', 'user.email').stdout.strip(), 'private@example.invalid')
        self.assertIn('out-of-scope', self.cli('doctor').stdout)
        self.commit()

    def test_supported_url_forms(self):
        for url in ('git@github.com:ExampleOwner/a.git', 'ssh://git@github.com/exampleowner/a.git',
                    'https://github.com/exampleowner/a.git'):
            with self.subTest(url=url):
                self.git('remote', 'set-url', 'origin', url)
                self.assertIn('protected', self.cli('doctor').stdout)

    def test_unmatched_case_and_pushurl_are_reported_unprotected(self):
        for url, pushurl in (('https://github.com/EXAMPLEOWNER/a.git', None),
                             ('https://github.com/OtherOwner/a.git', 'https://github.com/ExampleOwner/a.git')):
            with self.subTest(url=url):
                self.git('remote', 'set-url', 'origin', url)
                if pushurl:
                    self.git('remote', 'set-url', '--push', 'origin', pushurl)
                self.assertIn('not protected', self.cli('doctor', ok=False).stderr)

    def test_local_and_command_config_overrides_block(self):
        self.git('config', 'user.email', 'private@example.invalid')
        self.assertIn('Commit blocked', self.commit(ok=False).stderr)
        self.git('config', '--unset', 'user.email')
        result = self.git('-c', 'user.email=private@example.invalid', 'commit', '--allow-empty',
                          '-m', 'fixture', ok=False)
        self.assertIn('Commit blocked', result.stderr)
        self.git('rev-parse', '--verify', 'HEAD', ok=False)

    def test_environment_author_and_committer_overrides_block(self):
        for key in ('GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_EMAIL'):
            with self.subTest(key=key):
                env = dict(os.environ, **{key: 'private@example.invalid'})
                self.assertIn('Commit blocked', self.commit(env=env, ok=False).stderr)
        self.git('rev-parse', '--verify', 'HEAD', ok=False)

    def test_explicit_author_and_no_verify_block(self):
        self.assertIn('author email', self.commit('--author=Example Owner <private@example.invalid>', ok=False).stderr)
        env = dict(os.environ, GIT_COMMITTER_EMAIL='private@example.invalid')
        self.assertIn('Commit blocked', self.commit('--no-verify', env=env, ok=False).stderr)
        self.git('rev-parse', '--verify', 'HEAD', ok=False)

    def test_amend_retained_author_is_rejected_without_rewriting(self):
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '--allow-empty', '-m', 'old',
                 '--author=Example Owner <private@example.invalid>')
        before = self.git('rev-parse', 'HEAD').stdout
        self.assertIn('author email', self.commit('--amend', ok=False).stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, before)

    def test_legitimate_import_author_can_be_explicitly_allowed(self):
        previous = dict(self.policy)
        self.policy = dict(self.policy, allowed_author_emails=['contributor@example.invalid'])
        self.install([previous])
        self.commit('--author=Contributor <contributor@example.invalid>')
        self.assertEqual(self.git('show', '-s', '--format=%ae').stdout.strip(), 'contributor@example.invalid')

    def test_existing_precommit_failure_is_preserved(self):
        self.hook('pre-commit', 'echo project-hook >&2\nexit 42')
        result = self.commit(ok=False)
        self.assertIn('project-hook', result.stderr)
        self.git('rev-parse', '--verify', 'HEAD', ok=False)

    def test_other_project_hooks_receive_arguments(self):
        self.commit()
        target = self.root / 'post-checkout-args'
        self.hook('post-checkout', 'printf "%s\\n" "$@" > ' + str(target))
        self.git('checkout', '-b', 'other')
        self.assertEqual(len(target.read_text().splitlines()), 3)

    def test_worktree_shared_hooks_and_config_override(self):
        self.commit()
        target = self.root / 'precommit-ran'
        self.hook('pre-commit', 'printf yes > ' + str(target))
        worktree = self.root / 'worktree'
        self.git('worktree', 'add', '-b', 'linked', str(worktree))
        self.command('git', '-C', str(worktree), 'commit', '--allow-empty', '-m', 'linked')
        self.assertEqual(target.read_text(), 'yes')
        self.git('config', 'extensions.worktreeConfig', 'true')
        self.command('git', '-C', str(worktree), 'config', '--worktree', 'user.email', 'private@example.invalid')
        self.command('git', '-C', str(worktree), 'commit', '--allow-empty', '-m', 'bad', ok=False)

    def test_repository_hooks_override_is_not_silently_replaced(self):
        self.git('config', 'core.hooksPath', '.project-hooks')
        with self.assertRaisesRegex(identity.Blocked, 'core.hooksPath'):
            self.install()
        self.assertIn('not protected', self.cli('doctor', ok=False).stderr)
        self.assertEqual(self.git('config', 'core.hooksPath').stdout.strip(), '.project-hooks')

    def test_global_hook_manager_is_preserved(self):
        self.git('config', '--global', 'core.hooksPath', '/example/existing-hooks')
        with self.assertRaisesRegex(identity.Blocked, 'core.hooksPath'):
            self.install()
        self.assertEqual(self.git('config', '--global', 'core.hooksPath').stdout.strip(), '/example/existing-hooks')

    def test_included_global_hook_manager_is_preserved(self):
        included = self.home / 'other-config'
        included.write_text('[core]\n hooksPath = /example/existing-hooks\n')
        self.git('config', '--global', '--add', 'include.path', str(included))
        with self.assertRaisesRegex(identity.Blocked, 'core.hooksPath'):
            self.install()

    def test_system_hook_manager_is_preserved_and_conflict_blocks(self):
        hooks = self.root / 'system-hooks'
        hooks.mkdir()
        hook = hooks / 'pre-commit'
        hook.write_text('#!/bin/sh\nexit 42\n')
        hook.chmod(0o700)
        system = self.root / 'system-gitconfig'
        system.write_text('[core]\n hooksPath = ' + str(hooks) + '\n')
        with patch.dict(os.environ, {'GIT_CONFIG_SYSTEM': str(system), 'GIT_CONFIG_NOSYSTEM': '0'}):
            with self.assertRaisesRegex(identity.Blocked, 'core.hooksPath'):
                self.install()
            self.assertIn('not protected', self.cli('doctor', ok=False).stderr)
            self.assertIn('explicit integration', self.commit(ok=False).stderr)
        self.assertEqual(hook.read_text(), '#!/bin/sh\nexit 42\n')

    def test_conditional_hook_manager_is_checked_in_target_repository(self):
        self.commit()
        before = self.git('rev-parse', 'HEAD').stdout
        hooks = self.root / 'conditional-hooks'
        hooks.mkdir()
        for name, text in [('pre-commit', 'exit 42'),
                           ('post-checkout', 'touch ' + str(self.root / 'post-checkout-ran'))]:
            path = hooks / name
            path.write_text('#!/bin/sh\n' + text + '\n')
            path.chmod(0o700)
        config = self.home / 'project-config'
        config.write_text('[core]\n hooksPath = ' + str(hooks) + '\n')
        global_config = self.home / '.gitconfig'
        global_config.write_text('[includeIf "gitdir:' + str(self.repo) + '/"]\n path = ' + str(config) + '\n' + global_config.read_text())
        os.chdir(self.home)  # The conditional manager is invisible in the updater cwd.
        self.install()
        os.chdir(self.repo)
        self.assertIn('not protected', self.cli('doctor', ok=False).stderr)
        self.assertIn('explicit integration', self.commit(ok=False).stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, before)
        self.git('checkout', '-b', 'other')
        self.assertTrue((self.root / 'post-checkout-ran').is_file())

    def test_account_change_requires_scope_migration(self):
        previous = self.policy
        self.policy = dict(self.policy, github_login='AnotherOwner', email='1234+AnotherOwner@users.noreply.github.com')
        with self.assertRaisesRegex(identity.Blocked, 'account changed'):
            self.install([previous])
        self.assertEqual(json.loads((self.state / 'policy.json').read_text()), previous)

    def test_repeated_install_has_no_duplicate_includes(self):
        self.install()
        for pattern in identity.patterns(self.policy):
            value = self.git('config', '--global', '--get-all',
                             'includeIf.hasconfig:remote.*.url:' + pattern + '.path').stdout.splitlines()
            self.assertEqual(value, [str(self.state / 'gitconfig')])

    def test_edited_installation_is_preserved_and_rejected(self):
        target = self.state / 'hooks/pre-commit'
        target.write_text('# local edit\n')
        with self.assertRaisesRegex(identity.Blocked, 'differs from published'):
            self.install()
        self.assertEqual(target.read_text(), '# local edit\n')

    def test_deleted_or_nonexecutable_hook_is_rejected(self):
        target = self.state / 'hooks/pre-commit'
        target.chmod(0o600)
        with self.assertRaises(identity.Blocked):
            self.install()
        self.cli('doctor', ok=False)
        target.unlink()
        with self.assertRaises(identity.Blocked):
            self.install()

    def test_doctor_rejects_edited_executable_hook(self):
        (self.state / 'hooks/pre-commit').write_text('#!/bin/sh\nexit 0\n')
        self.assertIn('was edited', self.cli('doctor', ok=False).stderr)

    def brain_fixture(self):
        brain = self.root / 'brain'
        (brain / 'config').mkdir(parents=True)
        self.command('git', 'init', '-b', 'main', str(brain))
        policy = brain / 'config/git-identity.json'
        policy.write_text(json.dumps(self.policy) + '\n')
        self.command('git', '-C', str(brain), 'add', '.')
        self.command('git', '-C', str(brain), 'commit', '-m', 'policy')
        revision = self.command('git', '-C', str(brain), 'rev-parse', 'HEAD').stdout.strip()
        config = {'source': str(SOURCE.parent.parent), 'git_identity_policy': 'config/git-identity.json'}
        return brain, policy, revision, config

    def test_updater_installs_only_exact_committed_policy(self):
        brain, policy, revision, config = self.brain_fixture()
        self.assertEqual(sync.sync_identity(config, brain, revision, self.home)['status'], 'current')
        policy.write_text(policy.read_text() + '\n')
        with self.assertRaisesRegex(sync.Blocked, 'differs from the synchronized commit'):
            sync.sync_identity(config, brain, revision, self.home)

    def test_updater_accepts_published_prior_policy_but_rejects_symlink(self):
        brain, policy, revision, config = self.brain_fixture()
        self.policy = dict(self.policy, allowed_author_emails=['contributor@example.invalid'])
        policy.write_text(json.dumps(self.policy) + '\n')
        self.command('git', '-C', str(brain), 'commit', '-am', 'approved author')
        revision = self.command('git', '-C', str(brain), 'rev-parse', 'HEAD').stdout.strip()
        self.assertEqual(sync.sync_identity(config, brain, revision, self.home)['status'], 'current')
        self.assertEqual(json.loads((self.state / 'policy.json').read_text()), self.policy)
        replacement = self.root / 'policy-copy'
        policy.rename(replacement)
        policy.symlink_to(replacement)
        with self.assertRaisesRegex(sync.Blocked, 'must not use symlinks'):
            sync.sync_identity(config, brain, revision, self.home)

    def test_install_uses_fixed_permissions_under_restrictive_umask(self):
        old_umask = os.umask(0o077)
        self.addCleanup(os.umask, old_umask)
        second = self.home / 'second-identity'
        os.chdir(self.home)  # Install outside the first policy's repository scope.
        identity.install(self.policy, [], second, SOURCE, sys.executable)
        identity.verify_files(second, identity.files_for(self.policy, second, SOURCE, sys.executable))

    def push_fixture(self):
        remote = self.root / 'remote.git'
        self.command('git', 'init', '--bare', str(remote))
        self.git('remote', 'set-url', '--push', 'origin', str(remote))
        self.commit()
        self.git('push', '-u', 'origin', 'main')
        return remote

    def test_pre_push_forwards_stdin_and_project_failure(self):
        self.push_fixture()
        target = self.root / 'push-input'
        self.hook('pre-push', 'cat > ' + str(target) + '\nexit 42')
        self.commit()
        self.git('push', 'origin', 'main', ok=False)
        self.assertEqual(target.read_text().split()[0], 'refs/heads/main')
        self.assertEqual(len(target.read_text().split()), 4)

    def test_plumbing_commit_is_blocked_at_push_and_explicit_check(self):
        remote = self.push_fixture()
        before = self.git('rev-parse', 'HEAD').stdout.strip()
        tree = self.git('rev-parse', 'HEAD^{tree}').stdout.strip()
        env = dict(os.environ, GIT_AUTHOR_EMAIL='private@example.invalid')
        oid = self.git('commit-tree', tree, '-p', before, '-m', 'plumbing', env=env).stdout.strip()
        self.git('update-ref', 'refs/heads/main', oid)
        self.assertIn('Outgoing commit', self.git('push', 'origin', 'main', ok=False).stderr)
        self.assertIn('Outgoing commit', self.cli('check-range', before + '..' + oid, ok=False).stderr)
        published = self.command('git', '--git-dir=' + str(remote), 'rev-parse', 'refs/heads/main').stdout.strip()
        self.assertEqual(published, before)

    def test_new_branch_checks_only_destination_history(self):
        self.push_fixture()
        self.git('checkout', '-b', 'feature')
        self.commit()
        self.git('push', 'origin', 'feature')

    def test_existing_branch_preserves_other_already_published_authors(self):
        self.push_fixture()
        self.git('checkout', '-b', 'feature')
        self.commit()
        self.git('push', 'origin', 'feature')
        self.git('checkout', 'main')
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '--allow-empty', '-m', 'external',
                 '--author=Contributor <contributor@example.invalid>')
        self.git('-c', 'core.hooksPath=/dev/null', 'push', 'origin', 'main')
        self.git('checkout', 'feature')
        self.git('merge', '-m', 'merge published source', 'main')
        self.git('push', 'origin', 'feature')

    def test_different_destination_does_not_trust_stale_tracking_history(self):
        self.push_fixture()
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '--allow-empty', '-m', 'existing unsafe history',
                 '--author=Contributor <private@example.invalid>')
        self.git('-c', 'core.hooksPath=/dev/null', 'push', 'origin', 'main')
        destination = self.root / 'different-destination.git'
        self.command('git', 'init', '--bare', str(destination))
        self.git('remote', 'set-url', '--push', 'origin', str(destination))
        for changed_fetch in (False, True):
            with self.subTest(changed_fetch=changed_fetch):
                if changed_fetch:
                    self.git('remote', 'set-url', 'origin', 'https://github.com/ExampleOwner/replacement.git')
                self.assertIn('Outgoing commit', self.git('push', 'origin', 'main', ok=False).stderr)
                self.command('git', '--git-dir=' + str(destination), 'rev-parse', '--verify', 'refs/heads/main', ok=False)

    def test_merge_commit_checks_environment(self):
        self.commit()
        self.git('checkout', '-b', 'feature')
        self.commit()
        self.git('checkout', 'main')
        self.commit()
        before = self.git('rev-parse', 'HEAD').stdout
        env = dict(os.environ, GIT_COMMITTER_EMAIL='private@example.invalid')
        self.git('merge', '--no-ff', '-m', 'merge', 'feature', env=env, ok=False)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, before)

    def test_git_am_checks_committer_before_applying_commit(self):
        (self.repo / 'file').write_text('base')
        self.git('add', 'file')
        self.commit()
        before = self.git('rev-parse', 'HEAD').stdout.strip()
        (self.repo / 'file').write_text('patch')
        self.git('add', 'file')
        self.commit()
        patch_text = self.git('format-patch', '-1', '--stdout').stdout
        self.git('checkout', '-b', 'apply', before)
        env = dict(os.environ, GIT_COMMITTER_EMAIL='private@example.invalid')
        self.git('am', env=env, data=patch_text, ok=False)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), before)


if __name__ == '__main__':
    unittest.main()
