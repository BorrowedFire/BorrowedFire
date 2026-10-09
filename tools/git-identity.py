#!/usr/bin/env python3
"""Opt-in Git identity checks shared by local agent harnesses.

Account policy belongs in the private brain. The fleet updater installs it only from
published Git objects. Git hooks are accident prevention, not a security boundary
against a caller who deliberately disables hooks or replaces Git configuration.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


class Blocked(Exception):
    pass


# core.hooksPath replaces the entire hook directory. Forward even the hooks that
# do not check identity, so existing project automation continues to run.
HOOKS = (
    'applypatch-msg', 'pre-applypatch', 'post-applypatch', 'pre-commit',
    'pre-merge-commit', 'prepare-commit-msg', 'commit-msg', 'post-commit',
    'pre-rebase', 'post-checkout', 'post-merge', 'pre-push', 'pre-receive',
    'update', 'proc-receive', 'post-receive', 'post-update',
    'reference-transaction', 'push-to-checkout', 'pre-auto-gc', 'post-rewrite',
    'sendemail-validate', 'fsmonitor-watchman', 'p4-changelist',
    'p4-prepare-changelist', 'p4-post-changelist', 'p4-pre-submit', 'post-index-change',
)
COMMIT_HOOKS = {'pre-commit', 'prepare-commit-msg', 'pre-merge-commit', 'pre-applypatch'}


def git(*args, cwd=None, check=True):
    try:
        result = subprocess.run(['git', '--no-replace-objects', *args], cwd=cwd, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    except subprocess.TimeoutExpired:
        raise Blocked('Git inspection timed out: ' + args[0])
    if check and result.returncode:
        # Do not echo command output: it may contain private identity metadata.
        raise Blocked('Git could not inspect ' + args[0] + '; check repository state')
    return result


def policy_data(value):
    if not isinstance(value, dict) or value.get('version') != 1:
        raise Blocked('Unsupported Git identity policy')
    login, account_id = value.get('github_login'), value.get('github_id')
    if not isinstance(login, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', login):
        raise Blocked('Policy needs a verified GitHub login')
    if not isinstance(account_id, int) or isinstance(account_id, bool) or account_id <= 0:
        raise Blocked('Policy needs a verified GitHub account ID')
    expected = str(account_id) + '+' + login + '@users.noreply.github.com'
    if value.get('email') != expected:
        raise Blocked('Policy email does not match its verified GitHub account')
    authors = value.get('allowed_author_emails', [])
    if not isinstance(authors, list) or any(not isinstance(email, str) or not re.fullmatch(
            r'[^\s<>@]+@[^\s<>@]+', email) for email in authors):
        raise Blocked('Invalid allowed author emails')
    return value


def patterns(policy):
    # Git's hasconfig matching is case-sensitive. GitHub account names are not.
    # Common canonical and lowercase URL forms are enrolled; doctor reports other
    # spellings, host aliases and pushurl-only scope instead of claiming coverage.
    owners = sorted({policy['github_login'], policy['github_login'].lower()})
    return [prefix + owner + '/**' for owner in owners for prefix in (
        'https://github.com/', 'git@github.com:', 'ssh://git@github.com/',
    )]


def in_scope(policy):
    for remote in git('remote').stdout.splitlines():
        for direction in ((), ('--push',)):
            urls = git('remote', 'get-url', '--all', *direction, remote).stdout.splitlines()
            for url in urls:
                # Expanded URLs cover insteadOf aliases in the read-only doctor.
                match = re.match(r'^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+)/', url, re.I)
                if match and match[1].lower() == policy['github_login'].lower():
                    return True
    return False


def email_of(ident):
    match = re.search(r'<([^<>\n]+)> \d+ [+-]\d{4}\s*$', ident)
    if not match:
        raise Blocked('Git did not produce a complete commit identity')
    return match[1]


def check_emails(policy, author, committer, where):
    allowed = {policy['email'].lower(), *(email.lower() for email in policy.get('allowed_author_emails', []))}
    failures = []
    if author.lower() not in allowed:
        failures.append('author')
    if committer.lower() != policy['email'].lower():
        failures.append('committer')
    if failures:
        raise Blocked(where + ': ' + ' and '.join(failures) + ' email is not approved. '
                      'Use the verified account noreply identity; inspect local/worktree config, '
                      'git -c, GIT_AUTHOR_EMAIL, GIT_COMMITTER_EMAIL and --author. '
                      'Preserve imported attribution and existing commits; do not rewrite or bypass '
                      'the guard. A legitimate additional author needs an approved policy entry.')


def check_current(policy):
    check_emails(policy, email_of(git('var', 'GIT_AUTHOR_IDENT').stdout),
                 email_of(git('var', 'GIT_COMMITTER_IDENT').stdout), 'Commit blocked')


def check_commits(policy, revisions):
    if not revisions:
        return 0
    commits = git('rev-list', *revisions).stdout.splitlines()
    for commit in commits:
        fields = git('show', '-s', '--format=%ae%x00%ce', commit).stdout.rstrip('\n').split('\0')
        if len(fields) != 2:
            raise Blocked('Cannot inspect outgoing commit metadata')
        check_emails(policy, *fields, 'Outgoing commit ' + commit[:12] + ' blocked')
    return len(commits)


def destination_history(destination):
    """Only a destination's advertised refs establish that metadata is already there."""
    exclusions = []
    for line in git('ls-remote', '--refs', '--', destination).stdout.splitlines():
        fields = line.split()
        if len(fields) != 2 or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', fields[0]):
            raise Blocked('Cannot inspect push destination refs')
        # Unknown destination objects cannot exclude local commits. Conservatively
        # inspect more history until the caller fetches those objects.
        commit = git('rev-parse', '--verify', fields[0] + '^{commit}', check=False)
        if commit.returncode == 0:
            exclusions.append('^' + commit.stdout.strip())
    return exclusions


def check_push(policy, destination, data):
    count = 0
    published = None
    for line in data.decode().splitlines():
        fields = line.split()
        if len(fields) != 4:
            raise Blocked('Invalid pre-push input')
        _, local_oid, _, remote_oid = fields
        if not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', local_oid) or not re.fullmatch(
                r'[0-9a-f]{40}|[0-9a-f]{64}', remote_oid):
            raise Blocked('Invalid pre-push object ID')
        if set(local_oid) == {'0'}:
            continue  # Deleting a ref creates no commit metadata.
        # Tags may reference non-commit objects, which contain no commit identity.
        resolved = git('rev-parse', '--verify', local_oid + '^{commit}', check=False)
        if resolved.returncode:
            continue
        if published is None:
            published = destination_history(destination)
        revisions = [resolved.stdout.strip()]
        if set(remote_oid) != {'0'}:
            old = git('rev-parse', '--verify', remote_oid + '^{commit}', check=False)
            if old.returncode:
                raise Blocked('Fetch the push destination before checking its outgoing commits')
            revisions.append('^' + old.stdout.strip())
        revisions += published
        count += check_commits(policy, revisions)
    return count


def quote_config(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def configured_hooks():
    result = git('config', '--null', '--path', '--get-all', 'core.hooksPath', check=False)
    if result.returncode not in (0, 1):
        raise Blocked('Cannot inspect configured Git hook managers')
    return result.stdout.split('\0')[:-1] if result.returncode == 0 else []


def competing_hooks(state):
    managed = (state / 'hooks').resolve()
    return [Path(value).resolve() for value in configured_hooks() if Path(value).resolve() != managed]


def files_for(policy, state, source, python):
    state, source = state.resolve(), source.resolve()
    hook = '#!/bin/sh\nexec ' + ' '.join(shlex.quote(str(part)) for part in (
        python, '-B', source, 'hook', '--state', state,
    )) + ' "$0" "$@"\n'
    result = {
        'policy.json': (json.dumps(policy, indent=2, sort_keys=True) + '\n', 0o600),
        'binding.json': (json.dumps({'source': str(source), 'python': str(python)},
                                    indent=2, sort_keys=True) + '\n', 0o600),
        'gitconfig': ('[user]\n\temail = ' + quote_config(policy['email']) + '\n'
                      '[core]\n\thooksPath = ' + quote_config(state / 'hooks') + '\n', 0o600),
    }
    result.update({'hooks/' + name: (hook, 0o700) for name in HOOKS})
    return result


def verify_files(state, expected):
    if state.is_symlink() or not state.is_dir():
        raise Blocked('Git identity installation is missing or is a symlink')
    actual = set()
    for entry in state.rglob('*'):
        name = str(entry.relative_to(state))
        if entry.is_symlink():
            raise Blocked('Git identity installation contains a symlink; left untouched')
        if entry.is_file():
            actual.add(name)
        elif not entry.is_dir() or name != 'hooks':
            raise Blocked('Unexpected Git identity installation entry; left untouched')
    if actual != set(expected):
        raise Blocked('Git identity installation has missing or extra files; left untouched')
    for name, (content, mode) in expected.items():
        entry = state / name
        if entry.read_bytes() != content.encode() or entry.stat().st_mode & 0o777 != mode:
            raise Blocked('Git identity installation was edited: ' + name + '; left untouched')


def install(policy, previous, state, source, python):
    """Called by the updater with policy versions read from published brain objects."""
    policy_data(policy)
    if state.is_symlink():
        raise Blocked('Git identity installation is a symlink; left untouched')
    state, source = state.resolve(), source.resolve()
    expected = files_for(policy, state, source, python)
    # Inspect every active scope in the updater cwd. Conditional managers that are
    # visible only in a target repository are detected by doctor and dispatch.
    if competing_hooks(state):
        raise Blocked('Existing core.hooksPath needs explicit integration; left untouched')
    if state.exists() or state.is_symlink():
        verified = False
        for old_policy in [policy, *previous]:
            try:
                verify_files(state, files_for(policy_data(old_policy), state, source, python))
                verified = True
                break
            except Blocked:
                continue
        if not verified:
            raise Blocked('Git identity installation differs from published policy; left untouched')
        enrolled = json.loads((state / 'policy.json').read_text())
        if (enrolled['github_login'], enrolled['github_id']) != (policy['github_login'], policy['github_id']):
            raise Blocked('Enrolled GitHub account changed; review the scope migration before replacing includes')
    else:
        state.mkdir(parents=True, mode=0o700)
    (state / 'hooks').mkdir(exist_ok=True, mode=0o700)
    for name, (content, mode) in expected.items():
        target = state / name
        if target.exists() and target.read_bytes() == content.encode():
            continue
        fd, temporary = tempfile.mkstemp(dir=target.parent, prefix='.identity-')
        try:
            with os.fdopen(fd, 'w') as file:
                file.write(content)
            os.chmod(temporary, mode)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    for pattern in patterns(policy):
        key = 'includeIf.hasconfig:remote.*.url:' + pattern + '.path'
        existing = git('config', '--global', '--get-all', key, check=False)
        if existing.returncode not in (0, 1):
            raise Blocked('Cannot read global Git includes')
        if str(state / 'gitconfig') not in existing.stdout.splitlines():
            git('config', '--global', '--add', key, str(state / 'gitconfig'))
    verify_files(state, expected)
    return {'status': 'current', 'github_login': policy['github_login'],
            'state': str(state), 'coverage': 'conditional Git config; run doctor in each working repository'}


def doctor(policy, state):
    if not in_scope(policy):
        return {'status': 'out-of-scope', 'reason': 'No matching account-owned GitHub remote'}
    binding = json.loads((state / 'binding.json').read_text())
    if binding.get('source') != str(Path(__file__).resolve()) or not isinstance(binding.get('python'), str):
        raise Blocked('Git identity installation points to a different source; run the configured update check')
    verify_files(state, files_for(policy, state, Path(binding['source']), binding['python']))
    if competing_hooks(state):
        raise Blocked('Repository is not protected: another configured hook manager needs explicit '
                      'integration. Its configuration is preserved; do not disable it.')
    effective = git('config', '--path', '--get', 'core.hooksPath', check=False).stdout.strip()
    if not effective or Path(effective).resolve() != (state / 'hooks').resolve():
        raise Blocked('Repository is not protected: core.hooksPath is overridden or its remote URL '
                      'does not activate the managed include. Preserve existing hooks and integrate '
                      'them before committing; do not disable them.')
    check_current(policy)
    return {'status': 'protected', 'github_login': policy['github_login'],
            'author_and_committer': 'approved', 'hooks': str(state / 'hooks')}


def dispatch(policy, state, hook, args):
    data = None
    competing = competing_hooks(state)
    if in_scope(policy):
        if competing and hook in COMMIT_HOOKS | {'pre-push'}:
            raise Blocked('Another configured Git hook manager needs explicit integration before '
                          'committing or pushing. Its configuration is preserved; do not disable it.')
        if hook in COMMIT_HOOKS:
            check_current(policy)
        elif hook == 'pre-push':
            if len(args) != 2:
                raise Blocked('Invalid pre-push arguments')
            data = sys.stdin.buffer.read()
            check_push(policy, args[1], data)
    # --git-path hooks follows core.hooksPath and would recurse. Worktrees share
    # their original hooks in the common Git directory.
    common = Path(git('rev-parse', '--git-common-dir').stdout.strip()).resolve()
    # A conditional manager may only become visible in this repository. Commit and
    # push gates fail closed above. Preserve its other hooks (including post hooks)
    # until explicit integration, rather than silently skipping their behavior.
    original = (competing[-1] if competing else common / 'hooks') / hook
    if original.resolve() == (state / 'hooks' / hook).resolve():
        raise Blocked('Recursive Git hook configuration')
    if original.is_file() and os.access(original, os.X_OK):
        return subprocess.run([str(original), *args], input=data).returncode
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('doctor', 'check', 'check-range', 'hook'))
    parser.add_argument('--state', required=True, type=Path)
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_intermixed_args()
    try:
        state = args.state.expanduser().resolve()
        policy = policy_data(json.loads((state / 'policy.json').read_text()))
        if args.command == 'hook':
            if not args.arguments or Path(args.arguments[0]).name not in HOOKS:
                raise Blocked('Unknown Git hook')
            return dispatch(policy, state, Path(args.arguments[0]).name, args.arguments[1:])
        if args.command == 'doctor':
            print(json.dumps(doctor(policy, state)))
        elif args.command == 'check':
            check_current(policy)
            print('Git author and committer identity approved')
        else:
            if len(args.arguments) != 1 or not re.fullmatch(
                    r'[0-9a-f]{40}(?:\.\.[0-9a-f]{40})?', args.arguments[0]):
                raise Blocked('check-range requires a full commit SHA or full-SHA..full-SHA range')
            print(json.dumps({'checked_commits': check_commits(policy, args.arguments)}))
        return 0
    except (Blocked, OSError, ValueError) as exc:
        print('Git identity guard: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
