#!/usr/bin/env python3
"""Pull memory and install an explicitly reviewed Borrowed Fire revision."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import tempfile

class Blocked(Exception):
    pass

def run(args, cwd=None, timeout=180):
    env = dict(os.environ, GIT_NO_REPLACE_OBJECTS='1', GIT_TERMINAL_PROMPT='0', GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10')
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    previous_term = signal.signal(signal.SIGTERM, interrupted)
    proc = None
    try:
        proc = subprocess.Popen(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, start_new_session=True)
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        raise Blocked('Command timed out: ' + Path(args[0]).name)
    finally:
        # Finish cleanup before releasing the updater lock, even after interruption.
        previous_int = signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        try:
            if proc is not None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.communicate()
        finally:
            signal.signal(signal.SIGINT, previous_int)
            signal.signal(signal.SIGTERM, previous_term)
    if proc.returncode:
        raise Blocked('Command failed: ' + Path(args[0]).name + ' (exit ' + str(proc.returncode) + ')')
    return out.strip()

def git(repo, *args):
    return run(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args])

def clean(repo):
    if git(repo, 'status', '--porcelain'):
        raise Blocked('Checkout has local changes; left untouched')
    if any(entry and (entry[0].islower() or entry[0] == 'S')
           for entry in git(repo, 'ls-files', '-v', '-z').split('\0')):
        raise Blocked('Checkout has hidden index flags; left untouched')
    for marker in ('info/grafts', 'index.lock', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
                   'rebase-merge', 'rebase-apply', 'BISECT_LOG', 'BISECT_START'):
        path = Path(git(repo, 'rev-parse', '--git-path', marker))
        if not path.is_absolute():
            path = repo / path
        if path.exists():
            raise Blocked('Git operation in progress; left untouched')

def verify_source(repo, revision):
    """Compare the complete checkout with Git objects, without trusting index status."""
    expected = {}
    for entry in git(repo, 'ls-tree', '-r', '-t', '-z', revision).split('\0'):
        if not entry:
            continue
        metadata, name = entry.split('\t', 1)
        mode, kind, oid = metadata.split()
        expected[name] = (mode, None if kind == 'tree' else oid)
    algorithm = git(repo, 'rev-parse', '--show-object-format')
    actual = {}
    for item in repo.rglob('*'):
        relative = item.relative_to(repo)
        if relative.parts[0] == '.git':
            continue
        mode = item.lstat().st_mode
        data = None
        if stat.S_ISLNK(mode):
            entry_mode, data = '120000', os.fsencode(os.readlink(item))
        elif stat.S_ISREG(mode):
            entry_mode, data = ('100755' if mode & 0o111 else '100644'), item.read_bytes()
        elif stat.S_ISDIR(mode):
            entry_mode = '040000'
        else:
            raise Blocked('Unsupported source entry: ' + str(relative))
        oid = hashlib.new(algorithm, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() if data is not None else None
        actual[str(relative)] = (entry_mode, oid)
    if actual != expected:
        raise Blocked('Source entries differ from the committed revision; left untouched')

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

def release_record(brain, revision=None):
    current = git(brain, 'rev-parse', 'HEAD')
    if revision is not None and current != revision:
        raise Blocked('Brain changed during update; retry with synchronized state')
    revision = revision or current
    path = 'notes/borrowedfire-release-channel.md'
    text = git(brain, 'show', revision + ':' + path)
    local = brain / path
    if local.is_symlink() or not local.is_file():
        raise Blocked('Release record is not a regular committed file')
    data = local.read_bytes()
    algorithm = git(brain, 'rev-parse', '--show-object-format')
    oid = hashlib.new(algorithm, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if oid != git(brain, 'rev-parse', revision + ':' + path):
        raise Blocked('Release record differs from the synchronized commit')
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

def skill_entries(root):
    result = {}
    for item in root.rglob('*'):
        relative = item.relative_to(root)
        if relative == Path('.borrowedfire-copy') or '__pycache__' in relative.parts or item.suffix == '.pyc':
            continue
        mode = item.lstat().st_mode
        if stat.S_ISLNK(mode):
            value = ('link', os.readlink(item))
        elif stat.S_ISREG(mode):
            value = ('file', mode & 0o111, item.read_bytes())
        elif stat.S_ISDIR(mode):
            value = ('directory',)
        else:
            value = ('unsupported', stat.S_IFMT(mode))
        result[str(relative)] = value
    return result


def private_contexts(brain, path, revision, harnesses):
    """Read private instructions from synchronized Git objects, never from a status receipt."""
    if not isinstance(path, str):
        raise Blocked('Private context path must be a string')
    relative = Path(path)
    if relative.is_absolute() or '..' in relative.parts or relative.parts[:1] != ('config',) or relative.suffix != '.md':
        raise Blocked('Private context must be a Markdown file under brain config')
    local = brain / relative
    if any((brain / Path(*relative.parts[:i])).is_symlink() for i in range(1, len(relative.parts) + 1)):
        raise Blocked('Private context must not use symlinks')
    data = local.read_bytes()
    algorithm = git(brain, 'rev-parse', '--show-object-format')
    oid = hashlib.new(algorithm, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if oid != git(brain, 'rev-parse', revision + ':' + path):
        raise Blocked('Private context differs from the synchronized commit')

    def read(commit):
        entry = git(brain, 'ls-tree', commit, '--', path)
        if not entry.startswith(('100644 blob ', '100755 blob ')):
            raise Blocked('Private context is not a regular committed file')
        content = git(brain, 'show', commit + ':' + path)
        if content.startswith('---\n'):
            parts = content.split('---', 2)
            if len(parts) != 3:
                raise Blocked('Invalid private context frontmatter')
            content = parts[2].strip()
        begin = '<!-- BEGIN BORROWEDFIRE DOCTRINE -->'
        end = '<!-- END BORROWEDFIRE DOCTRINE -->'
        if content.count(begin) != 1 or content.count(end) != 1 or content.index(begin) >= content.index(end):
            raise Blocked('Private context needs one ordered managed doctrine block')
        return content + '\n'

    current = read(revision)
    installed = {Path(h['context']).read_bytes().decode() for h in harnesses}
    known = [current]
    # Usually the current version is enough. Consult published history only to recognize an
    # earlier installation. Missing/corrupt status receipts cannot authorize unknown edits.
    if not installed.issubset(set(known)):
        for commit in git(brain, 'rev-list', revision, '--', path).splitlines():
            try:
                previous = read(commit)
            except Blocked:
                continue  # A deleted file or old pre-enrollment format is not installable.
            if previous not in known:
                known.append(previous)
            if installed.issubset(set(known)):
                break
    return known


def verify_install(repo, harnesses, contexts=None):
    expected = (repo / 'doctrine/DOCTRINE.md').read_text().strip()
    begin = '<!-- BEGIN BORROWEDFIRE DOCTRINE -->'
    end = '<!-- END BORROWEDFIRE DOCTRINE -->'
    for harness in harnesses:
        context = Path(harness['context'])
        actual = context.read_bytes().decode()
        private = contexts.get(str(context)) if contexts is not None else None
        if private is not None and actual not in private:
            raise Blocked('Installed private context has local changes; reconcile before updating')
        if actual.count(begin) != 1 or actual.count(end) != 1:
            raise Blocked('Installed doctrine must have exactly one managed block: ' + str(context))
        block = actual[actual.index(begin):actual.index(end) + len(end)].strip()
        if private is None and block != expected:
            raise Blocked('Installed doctrine differs from reviewed source: ' + str(context))
        skills = Path(harness['skills'])
        modes = {}
        for line in (skills / '.borrowedfire-manifest').read_text().splitlines():
            parts = line.split()
            if len(parts) != 2 or parts[0] in modes:
                raise Blocked('Invalid installed ownership manifest')
            modes[parts[0]] = parts[1]
        sources = [source for source in (repo / 'skills').iterdir() if source.is_dir()]
        if set(modes) != {source.name for source in sources}:
            raise Blocked('Installed ownership differs from current source skills')
        for source in sources:
            installed = skills / source.name
            mode = modes.get(source.name)
            if mode == 'link':
                if not installed.is_symlink() or installed.resolve() != source.resolve():
                    raise Blocked('Installed link ownership differs: ' + source.name)
            elif mode == 'copy':
                marker = installed / '.borrowedfire-copy'
                if installed.is_symlink() or not marker.is_file() or marker.is_symlink():
                    raise Blocked('Installed copy ownership differs: ' + source.name)
            else:
                raise Blocked('Missing installed ownership: ' + source.name)
            if skill_entries(source) != skill_entries(installed):
                raise Blocked('Installed skill entries differ from reviewed source: ' + source.name)


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


def sync_source(config, brain, prior, brain_revision=None):
    repo = Path(config['source'])
    if discovered_harnesses(config) != config['harnesses']:
        raise Blocked('Installed harness set changed; reconcile updater configuration first')
    clean(repo)
    try:
        branch = git(repo, 'symbolic-ref', '--short', 'HEAD')
    except Blocked:
        branch = None
    if branch != 'main':
        raise Blocked('Source is not on main; left untouched')
    head = git(repo, 'rev-parse', 'HEAD')
    verify_source(repo, head)
    approved = release_record(brain, brain_revision)
    contexts = None
    private = []
    if config.get('private_context'):
        revision = brain_revision or git(brain, 'rev-parse', 'HEAD')
        targets = config.get('private_context_targets', [h['context'] for h in config['harnesses']])
        if not isinstance(targets, list) or not targets or any(
                target not in [h['context'] for h in config['harnesses']] for target in targets):
            raise Blocked('Private context targets must be enrolled harnesses')
        private = [h for h in config['harnesses'] if h['context'] in targets]
        destinations = {}
        for harness in config['harnesses']:
            target = Path(harness['context']).resolve()
            selected = harness in private
            if target in destinations and destinations[target] != selected:
                raise Blocked('A shared context cannot mix public and private instruction sources')
            destinations[target] = selected
        known = private_contexts(brain, config['private_context'], revision, private)
        contexts = {h['context']: known for h in private}
    context_changed = contexts is not None and any(
        Path(h['context']).read_bytes().decode() != contexts[h['context']][0] for h in private)
    git(repo, 'fetch', 'origin', 'main')
    latest = git(repo, 'rev-parse', 'FETCH_HEAD')
    if not ancestor(repo, approved, latest):
        raise Blocked('Approved revision is not in published main')
    if not ancestor(repo, head, approved):
        raise Blocked('Installed source has local or newer commits; reconciliation required')
    if head == approved and prior.get('revision') == approved and prior.get('status') == 'current' and not context_changed:
        verify_install(repo, config['harnesses'], contexts)
    else:
        # Copied skills can contain owner edits even when the source Git tree is clean.
        verify_install(repo, config['harnesses'], contexts)
        clean(repo)
        git(repo, 'merge', '--ff-only', approved)
        verify_source(repo, approved)
        run(['bash', 'tools/skill-lint.sh'], cwd=repo)
        args = ['bash', 'install.sh', '--brain', str(brain)]
        if config.get('copy'):
            args.append('--copy')
        if config.get('openclaw_workspace'):
            args += ['--openclaw-workspace', config['openclaw_workspace']]
        # Keep the private contents outside the public checkout, including during failures.
        with tempfile.TemporaryDirectory(prefix='borrowedfire-context-') as directory:
            if contexts is not None:
                context_file = Path(directory) / 'AGENTS.md'
                context_file.write_text(next(iter(contexts.values()))[0])
                context_file.chmod(0o600)
                args += ['--context-file', str(context_file)]
                for harness in private:
                    args += ['--context-target', harness['context']]
            run(args, cwd=repo, timeout=300)
        verify_source(repo, approved)
        verify_install(repo, config['harnesses'], {path: versions[:1] for path, versions in contexts.items()}
                       if contexts is not None else None)
    return {'status': 'current', 'revision': approved, 'upstream_revision': latest,
            'awaiting_review': latest != approved}

def write_json(path, data):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.status-')
    with os.fdopen(fd, 'w') as file:
        json.dump(data, file, indent=2)
        file.write('\n')
    os.replace(name, path)

def read_status(path):
    # This is an optional performance receipt, never installation authority.
    try:
        prior = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    if not isinstance(prior, dict):
        return {}
    if not isinstance(prior.get('borrowedfire'), dict):
        prior['borrowedfire'] = {}
    return prior

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
        prior = read_status(status_path)
        status = {'checked_at': dt.datetime.now(dt.timezone.utc).isoformat()}
        brain = Path(config['brain'])
        for name, operation in [('prometheus', lambda: sync_brain(brain)),
                                ('borrowedfire', lambda: sync_source(config, brain, prior.get('borrowedfire', {}),
                                                                    status['prometheus']['revision']))]:
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
