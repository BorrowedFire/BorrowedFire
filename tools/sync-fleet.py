#!/usr/bin/env python3
"""Pull memory and install an explicitly reviewed Borrowed Fire revision."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile

class Blocked(Exception):
    pass

def run(args, cwd=None, timeout=180):
    env = dict(os.environ, GIT_NO_REPLACE_OBJECTS='1', GIT_TERMINAL_PROMPT='0', GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10')
    proc = subprocess.Popen(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise Blocked('Command timed out: ' + Path(args[0]).name)
    if proc.returncode:
        raise Blocked('Command failed: ' + Path(args[0]).name + ' (exit ' + str(proc.returncode) + ')')
    return out.strip()

def git(repo, *args):
    return run(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args])

def clean(repo):
    if git(repo, 'status', '--porcelain'):
        raise Blocked('Checkout has local changes; left untouched')
    for marker in ('info/grafts', 'index.lock', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply'):
        path = Path(git(repo, 'rev-parse', '--git-path', marker))
        if not path.is_absolute():
            path = repo / path
        if path.exists():
            raise Blocked('Git operation in progress; left untouched')

def ancestor(repo, older, newer):
    try:
        git(repo, 'merge-base', '--is-ancestor', older, newer)
    except Blocked:
        return False
    return True

def sync_brain(repo):
    clean(repo)
    branch = git(repo, 'symbolic-ref', '--short', 'HEAD')
    if branch != 'main':
        raise Blocked('Brain is not on main; left untouched')
    git(repo, 'fetch', 'origin', 'main')
    target = git(repo, 'rev-parse', 'FETCH_HEAD')
    head = git(repo, 'rev-parse', 'HEAD')
    if not ancestor(repo, head, target):
        raise Blocked('Brain has unpushed or divergent commits; left untouched')
    clean(repo)
    git(repo, 'merge', '--ff-only', target)
    return {'status': 'current', 'revision': target}

def release_record(brain):
    text = (brain / 'notes/borrowedfire-release-channel.md').read_text()
    front = text.split('---', 2)
    if len(front) != 3 or front[0].strip():
        raise Blocked('Invalid reviewed release record')
    fields = {}
    for line in front[1].splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            if key in fields:
                raise Blocked('Duplicate release field')
            fields[key] = value.strip()
    rev = fields.get('release_commit', '')
    if not re.fullmatch(r'[0-9a-f]{40}', rev) or fields.get('release_status') != 'approved':
        raise Blocked('No approved release revision')
    if not re.fullmatch(r'https://github.com/BorrowedFire/BorrowedFire/pull/[0-9]+', fields.get('review_url', '')):
        raise Blocked('Approved release lacks a review reference')
    return rev

def verify_install(repo, harnesses):
    expected = (repo / 'doctrine/DOCTRINE.md').read_text().strip()
    for harness in harnesses:
        context = Path(harness['context'])
        actual = context.read_text()
        if expected not in actual:
            raise Blocked('Installed doctrine differs from reviewed source: ' + str(context))
        skills = Path(harness['skills'])
        for source in (repo / 'skills').iterdir():
            if not source.is_dir():
                continue
            installed = skills / source.name
            source_files = {str(p.relative_to(source)) for p in source.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc'}
            installed_files = {str(p.relative_to(installed)) for p in installed.rglob('*') if p.is_file() and p.name != '.borrowedfire-copy' and '__pycache__' not in p.parts and p.suffix != '.pyc'}
            if installed_files != source_files:
                raise Blocked('Installed skill has missing or extra files: ' + source.name)
            for item in source.rglob('*'):
                if item.is_file() and '__pycache__' not in item.parts and item.suffix != '.pyc':
                    target = skills / source.name / item.relative_to(source)
                    if not target.is_file() or item.read_bytes() != target.read_bytes():
                        raise Blocked('Installed skill differs from reviewed source: ' + source.name)

def discovered_harnesses(config):
    home = Path.home()
    found = []
    for root, context in [(home / '.claude', 'CLAUDE.md'),
                          (Path(os.environ.get('CODEX_HOME', home / '.codex')), 'AGENTS.md'),
                          (home / '.qwen', 'QWEN.md')]:
        if root.is_dir():
            found.append({'skills': str(root / 'skills'), 'context': str(root / context)})
    if config.get('openclaw_workspace'):
        root = Path(config['openclaw_workspace'])
        if not root.is_dir():
            raise Blocked('Configured OpenClaw workspace is unavailable')
        found.append({'skills': str(root / 'skills'), 'context': str(root / 'AGENTS.md')})
    return found


def sync_source(config, brain, prior):
    repo = Path(config['source'])
    if discovered_harnesses(config) != config['harnesses']:
        raise Blocked('Installed harness set changed; reconcile updater configuration first')
    clean(repo)
    approved = release_record(brain)
    git(repo, 'fetch', 'origin', 'main')
    latest = git(repo, 'rev-parse', 'FETCH_HEAD')
    head = git(repo, 'rev-parse', 'HEAD')
    if not ancestor(repo, approved, latest):
        raise Blocked('Approved revision is not in published main')
    if not ancestor(repo, head, approved):
        raise Blocked('Installed source has local or newer commits; reconciliation required')
    if head == approved and prior.get('revision') == approved and prior.get('status') == 'current':
        verify_install(repo, config['harnesses'])
    else:
        # Copied skills can contain owner edits even when the source Git tree is clean.
        verify_install(repo, config['harnesses'])
        clean(repo)
        git(repo, 'merge', '--ff-only', approved)
        run(['bash', 'tools/skill-lint.sh'], cwd=repo)
        args = ['bash', 'install.sh', '--brain', str(brain)]
        if config.get('copy'):
            args.append('--copy')
        if config.get('openclaw_workspace'):
            args += ['--openclaw-workspace', config['openclaw_workspace']]
        run(args, cwd=repo, timeout=300)
        verify_install(repo, config['harnesses'])
    return {'status': 'current', 'revision': approved, 'upstream_revision': latest,
            'awaiting_review': latest != approved}

def write_json(path, data):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.status-')
    with os.fdopen(fd, 'w') as file:
        json.dump(data, file, indent=2)
        file.write('\n')
    os.replace(name, path)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    config_path = Path(args.config).resolve()
    config = json.loads(config_path.read_text())
    state = config_path.parent
    with (state / 'sync.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        status_path = state / 'status.json'
        prior = json.loads(status_path.read_text()) if status_path.exists() else {}
        status = {'checked_at': dt.datetime.now(dt.timezone.utc).isoformat()}
        brain = Path(config['brain'])
        for name, operation in [('prometheus', lambda: sync_brain(brain)),
                                ('borrowedfire', lambda: sync_source(config, brain, prior.get('borrowedfire', {})))]:
            try:
                # Do not authorize an installation from a stale, busy, or conflicted brain.
                if name == 'borrowedfire' and status['prometheus']['status'] != 'current':
                    raise Blocked('Waiting for a clean, current Prometheus checkout')
                status[name] = operation()
            except (Blocked, OSError, ValueError) as exc:
                status[name] = {'status': 'blocked', 'reason': str(exc)}
        write_json(status_path, status)
        print(json.dumps(status))
        return int(any(status[key]['status'] != 'current' for key in ('prometheus', 'borrowedfire')))

if __name__ == '__main__':
    raise SystemExit(main())
