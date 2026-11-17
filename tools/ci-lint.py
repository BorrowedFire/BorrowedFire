#!/usr/bin/env python3
"""Report private-repository workflows that waste shared self-hosted runner time.

Read-only. For each private GitHub repository checked out under the root, this reads the
workflows committed on the remote-tracking default branch and flags:

1. A workflow triggered by pull requests without the PR-only cancelling concurrency block.
2. A job whose runs-on is not exactly the [self-hosted, studio] label set.

Public repositories are exempt. It never fetches, edits, or commits.
Exit status: 0 clean, 1 findings, 2 errors without findings.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

DEFAULT_ROOT = Path.home() / 'Developer/BorrowedFire'
DEFAULT_CACHE = Path.home() / '.cache/borrowedfire/ci-lint.json'
DEFAULT_OWNER = 'BorrowedFire'
SEARCH = ('Apps/*', 'Website/*', 'BorrowedFire')
CACHE_DAYS = 7
BUDGET_SECONDS = 90  # Stay inside the session update check's 120-second limit.
REQUIRED_CANCEL = "${{ github.event_name == 'pull_request' }}"
REQUIRED_LABELS = {'self-hosted', 'studio'}
PER_RUN = r'\bgithub\.(?:run_id|run_number|run_attempt|sha)\b'
PR_TRIGGERS = {'pull_request', 'pull_request_target'}


class ParseError(Exception):
    pass


# --- Minimal YAML reader -------------------------------------------------------------------
# Workflows use a small, regular part of YAML. This reads block mappings, block sequences,
# flow collections (nested, spanning lines), quoted and plain scalars, block scalars, and
# anchors with aliases. Tags are kept as raw strings, which check_workflow rejects where the
# rule reads them, so an unsupported form becomes an error instead of a silent pass.

def strip_comment(text):
    quote = None
    for index, char in enumerate(text):
        if quote:
            if char == quote:
                quote = None
        elif char in '"\'' and (index == 0 or text[index - 1] in ' \t[,:-'):
            quote = char
        elif char == '#' and (index == 0 or text[index - 1] in ' \t'):
            return text[:index].rstrip()
    return text.rstrip()


class Unterminated(ParseError):
    pass


def scalar(text):
    text = text.strip()
    if text[:1] in ('[', '{'):
        value, end = flow(text, 0)
        if text[end:].strip():
            raise ParseError('text after a flow collection: ' + text[:60])
        return value
    if len(text) >= 2 and text[0] == text[-1] and text[0] in '"\'':
        inner = text[1:-1]
        return inner.replace("''", "'") if text[0] == "'" else inner
    return text


def flow(text, index):
    """Parse the flow collection or scalar at text[index]; return (value, next index)."""
    while index < len(text) and text[index] == ' ':
        index += 1
    if index >= len(text):
        raise Unterminated('unterminated flow collection: ' + text[:60])
    opener = text[index]
    if opener not in '[{':
        start = index
        index = flow_token_end(text, index, ',]}')
        return scalar(text[start:index]), index
    closer = ']' if opener == '[' else '}'
    result = [] if opener == '[' else {}
    index += 1
    while True:
        while index < len(text) and text[index] == ' ':
            index += 1
        if index >= len(text):
            raise Unterminated('unterminated flow collection: ' + text[:60])
        if text[index] == closer:
            return result, index + 1
        if opener == '[':
            value, index = flow(text, index)
            if value == '':
                raise ParseError('empty flow sequence entry: ' + text[:60])
            result.append(value)
        else:
            start = index
            index = flow_token_end(text, index, ':,}')
            key = scalar(text[start:index])
            if index < len(text) and text[index] == ':':
                value, index = flow(text, index + 1)
            else:
                value = None
            result[key] = value
        while index < len(text) and text[index] == ' ':
            index += 1
        if index < len(text) and text[index] == ',':
            index += 1
        elif index < len(text) and text[index] != closer:
            raise ParseError('expected , or ' + closer + ' in: ' + text[:60])


def flow_token_end(text, index, stops):
    """Find where a plain or quoted flow scalar ends, keeping ${{ }} expressions whole."""
    if text[index] in '"\'':
        quote = text[index]
        index += 1
        while index < len(text):
            if text[index] == quote:
                if quote == "'" and text[index + 1:index + 2] == "'":
                    index += 2
                    continue
                return index + 1
            index += 1
        raise Unterminated('unterminated quoted scalar: ' + text[:60])
    while index < len(text):
        if text.startswith('${{', index):
            close = text.find('}}', index + 3)
            if close < 0:
                raise Unterminated('unterminated expression: ' + text[:60])
            index = close + 2
            continue
        char = text[index]
        if char in '[{':
            raise ParseError('unexpected ' + char + ' in flow scalar: ' + text[:60])
        if char in stops and (char != ':' or text[index + 1:index + 2] in ('', ' ', ',', '}')):
            return index
        index += 1
    return index


def split_key(text):
    """Return (key, rest) for a mapping line, or None."""
    if text and text[0] in '"\'':
        end = text.find(text[0], 1)
        if end > 0 and text[end + 1:end + 2] == ':' and text[end + 2:end + 3] in ('', ' '):
            return text[1:end], text[end + 2:].strip()
        return None
    match = re.match(r'([^\s:#\[\]{},][^:#]*?)\s*:(?:\s+|$)(.*)$', text)
    if not match:
        return None
    return match.group(1), match.group(2).strip()


class Reader:
    def __init__(self, text):
        self.raw = text.lstrip('\ufeff').replace('\t', '    ').splitlines()
        self.lines = []  # (indent, content) with comments removed; None for blank lines
        self.anchors = {}
        for line in self.raw:
            content = strip_comment(line)
            if not content.strip() or content.strip() in ('---', '...'):
                self.lines.append(None)
            else:
                self.lines.append((len(content) - len(content.lstrip(' ')), content.strip()))

    def next_index(self, index):
        while index < len(self.lines) and self.lines[index] is None:
            index += 1
        return index

    def parse(self):
        index = self.next_index(0)
        if index >= len(self.lines):
            return {}
        value, index = self.block(index, self.lines[index][0])
        index = self.next_index(index)
        if index < len(self.lines):
            raise ParseError('unexpected indentation at line ' + str(index + 1))
        return value

    def block(self, index, indent):
        if self.lines[index][1] == '-' or self.lines[index][1].startswith('- '):
            return self.sequence(index, indent)
        return self.mapping(index, indent)

    def block_scalar(self, index, indent):
        lines = []
        while index < len(self.raw):
            line = self.raw[index]
            if line.strip() and len(line) - len(line.lstrip(' ')) <= indent:
                break
            lines.append(line.strip())
            index += 1
        return '\n'.join(lines).strip(), index

    def value_after_key(self, rest, index, indent):
        """Parse what follows `key:` whose line is index - 1."""
        anchor = None
        if rest.startswith('&'):
            anchor, _, rest = rest.partition(' ')
            rest = rest.strip()
        value, index = self.plain_value(rest, index, indent)
        if anchor:
            self.anchors[anchor[1:]] = value
        return value, index

    def plain_value(self, rest, index, indent):
        if rest.startswith('*'):
            if rest[1:] not in self.anchors:
                raise ParseError('unknown alias ' + rest)
            return self.anchors[rest[1:]], index
        if rest and rest[0] in '|>':
            return self.block_scalar(index, indent)
        if rest and rest[0] == '!':
            return rest, index  # tags: keep raw so checks fail visibly
        if rest:
            # Scalars and flow collections continue on more-indented lines; join them, then
            # parse the whole value so a multi-line [a,\n b] is read as a list, not a string.
            following = self.next_index(index)
            while following < len(self.lines) and self.lines[following][0] > indent:
                rest += ' ' + self.lines[following][1]
                index = following + 1
                following = self.next_index(index)
            while True:
                try:
                    return scalar(rest), index
                except Unterminated:
                    # A flow collection may close on a line at the key's own indent.
                    if rest[:1] not in ('[', '{') or following >= len(self.lines):
                        raise
                    rest += ' ' + self.lines[following][1]
                    index = following + 1
                    following = self.next_index(index)
        following = self.next_index(index)
        if following >= len(self.lines):
            return None, following
        child_indent, content = self.lines[following]
        if child_indent > indent or (child_indent == indent and (content == '-' or content.startswith('- '))):
            return self.block(following, child_indent)
        return None, index

    def mapping(self, index, indent):
        result = {}
        while True:
            index = self.next_index(index)
            if index >= len(self.lines):
                return result, index
            current, content = self.lines[index]
            if current < indent or content == '-' or content.startswith('- '):
                return result, index
            if current > indent:
                raise ParseError('unexpected indentation at line ' + str(index + 1))
            pair = split_key(content)
            if pair is None:
                raise ParseError('expected a key at line ' + str(index + 1))
            key, rest = pair
            result[key], index = self.value_after_key(rest, index + 1, indent)

    def sequence(self, index, indent):
        result = []
        while True:
            index = self.next_index(index)
            if index >= len(self.lines):
                return result, index
            current, content = self.lines[index]
            if current != indent or not (content == '-' or content.startswith('- ')):
                if current > indent:
                    raise ParseError('unexpected indentation at line ' + str(index + 1))
                return result, index
            item = content[1:].strip()
            if not item:
                following = self.next_index(index + 1)
                if following < len(self.lines) and self.lines[following][0] > indent:
                    value, index = self.block(following, self.lines[following][0])
                else:
                    value, index = None, index + 1
            elif split_key(item) is not None and item[0] not in '[{':
                # "- key: value" starts a mapping indented to where the key begins.
                offset = indent + len(content) - len(item)
                self.lines[index] = (offset, item)
                value, index = self.mapping(index, offset)
            else:
                value, index = scalar(item), index + 1
            result.append(value)


def load_yaml(text):
    return Reader(text).parse()


# --- Rule checks ---------------------------------------------------------------------------

def raw(value):
    return isinstance(value, str) and value[:1] in ('{', '&', '*', '!')


def triggers(workflow):
    on = workflow.get('on', workflow.get('true'))
    if isinstance(on, str) and on and not raw(on):
        return {on}
    if isinstance(on, list) and all(isinstance(item, str) and not raw(item) for item in on):
        return set(on)
    if isinstance(on, dict):
        return set(on)
    raise ParseError('unsupported or missing on: triggers')


def compact(text):
    return re.sub(r'\s+', ' ', text.strip()) if isinstance(text, str) else text


def check_workflow(text, owner=None):
    """Return a list of problems for one workflow file. Raises ParseError."""
    workflow = load_yaml(text)
    if not isinstance(workflow, dict):
        raise ParseError('workflow is not a mapping')
    problems = []
    if triggers(workflow) & PR_TRIGGERS:
        concurrency = workflow.get('concurrency')
        if not isinstance(concurrency, dict):
            problems.append('runs on pull requests without the PR-only concurrency block')
        else:
            group = concurrency.get('group')
            # Only text inside ${{ }} is evaluated; a literal "github.ref" is a constant group.
            expressions = ' '.join(re.findall(r'\$\{\{(.*?)\}\}', group)) if isinstance(group, str) else ''
            if not (re.search(r'\bgithub\.workflow\b', expressions)
                    and re.search(r'\bgithub\.ref\b(?!_)', expressions)):
                problems.append('concurrency group must include github.workflow and github.ref')
            elif re.search(PER_RUN, expressions):
                # A value unique to each run or push gives every run its own group, so nothing cancels.
                problems.append('concurrency group must not include a per-run value such as '
                                'github.run_id or github.sha')
            cancel = compact(concurrency.get('cancel-in-progress'))
            if cancel != REQUIRED_CANCEL:
                shown = 'missing' if cancel is None else repr(cancel)
                problems.append('cancel-in-progress is ' + shown + '; must be ' + REQUIRED_CANCEL
                                + ' so only superseded PR runs cancel')
    jobs = workflow.get('jobs')
    if not isinstance(jobs, dict):
        raise ParseError('jobs is not a block mapping')
    for name, job in jobs.items():
        if not isinstance(job, dict):
            raise ParseError('job ' + name + ' is not a block mapping')
        runs_on = job.get('runs-on')
        if runs_on is None and 'uses' in job:
            called = job['uses']
            # A local or same-owner workflow is checked in its own repository. Another owner's
            # workflow picks its own runner, which this tool cannot see.
            if not (isinstance(called, str) and (called.startswith('./') or (
                    owner and called.lower().startswith(owner.lower() + '/')))):
                problems.append('job ' + name + ' calls ' + json.dumps(called)
                                + '; a reusable workflow outside this owner cannot be checked'
                                + ' for [self-hosted, studio]')
            continue
        labels = runs_on.get('labels') if isinstance(runs_on, dict) else runs_on
        if isinstance(labels, str):
            labels = [labels]
        if not (isinstance(labels, list) and all(isinstance(label, str) for label in labels)
                and {label.strip() for label in labels} == REQUIRED_LABELS and len(labels) == 2):
            problems.append('job ' + name + ' runs-on ' + json.dumps(runs_on)
                            + '; must be [self-hosted, studio]')
    return problems


# --- Repository discovery ------------------------------------------------------------------

DEADLINE = [None]  # Set by lint(); keeps each call inside the overall time budget.


def command(args, cwd=None, timeout=15):
    if DEADLINE[0] is not None:
        timeout = max(1, min(timeout, DEADLINE[0] - time.monotonic()))
    proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                          env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GH_PROMPT_DISABLED='1'))
    if proc.returncode:
        raise RuntimeError((proc.stderr.strip().splitlines() or ['exit ' + str(proc.returncode)])[-1])
    return proc.stdout


def git(repo, *args):
    return command(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args])


def github_name(url, owner):
    match = re.match(r'(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+)/(.+?)(?:\.git)?/?$',
                     url.strip())
    if match and match.group(1).lower() == owner.lower():
        return match.group(1) + '/' + match.group(2)
    return None


def checkouts(root, owner, errors):
    """Map each owner/name to the local checkouts whose origin points at it.

    A checkout with no origin remote is not one of the owner's repositories. Any other git failure
    is recorded in errors, so a broken git never reads as a clean run.
    """
    found = {}
    for pattern in SEARCH:
        for path in sorted(root.glob(pattern)):
            if not (path / '.git').exists():
                continue
            try:
                remotes = git(path, 'remote').split()
                if 'origin' not in remotes:
                    continue
                url = git(path, 'remote', 'get-url', 'origin')
            except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
                errors.append({'repository': None, 'checkout': str(path),
                               'problem': 'cannot read origin of ' + str(path) + ': ' + str(exc)})
                continue
            name = github_name(url, owner)
            if name:
                found.setdefault(name.lower(), (name, []))[1].append(path)
    return found


def read_cache(path):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def write_cache(path, data):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name('.' + path.name + '.tmp')
        temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
        os.replace(temporary, path)
    except OSError:
        pass  # The cache only saves gh calls; losing it is harmless.


def repository_info(name, cache, gh, now):
    entry = cache.get(name.lower())
    if isinstance(entry, dict):
        try:
            age = now - dt.datetime.fromisoformat(entry['checked_at'])
            if age < dt.timedelta(days=CACHE_DAYS) and entry.get('visibility') and entry.get('default_branch'):
                return entry
        except (KeyError, TypeError, ValueError):
            pass
    data = json.loads(command([gh, 'repo', 'view', name, '--json', 'visibility,defaultBranchRef']))
    entry = {'visibility': str(data['visibility']).upper(),
             'default_branch': data['defaultBranchRef']['name'],
             'checked_at': now.isoformat()}
    cache[name.lower()] = entry
    return entry


def newest_ref(paths, branch):
    """Pick the checkout whose copy of the default branch has the newest commit."""
    best = None
    for path in paths:
        for ref in ('refs/remotes/origin/' + branch, 'refs/heads/' + branch):
            try:
                revision, stamp = git(path, 'log', '-1', '--format=%H %ct', ref, '--').split()
            except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired):
                continue
            if best is None or int(stamp) > best[2]:
                best = (path, revision, int(stamp))
            break
    return best


def lint(root, cache_path, gh='gh', owner=DEFAULT_OWNER, budget=BUDGET_SECONDS):
    report = {'findings': [], 'errors': [], 'exempt': [], 'checked': [], 'stale': []}
    root = Path(root).expanduser()
    if not root.is_dir():
        report['errors'].append({'repository': None, 'problem': 'root not found: ' + str(root)})
        return report
    cache = read_cache(cache_path)
    now = dt.datetime.now(dt.timezone.utc)
    deadline = time.monotonic() + budget
    DEADLINE[0] = deadline
    for _, (name, paths) in sorted(checkouts(root, owner, report['errors']).items()):
        if time.monotonic() > deadline:
            report['errors'].append({'repository': name, 'problem': 'time budget spent, skipped'})
            continue
        try:
            info = repository_info(name, cache, gh, now)
        except (RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as exc:
            report['errors'].append({'repository': name, 'problem': 'visibility unknown, skipped: ' + str(exc)})
            continue
        if info['visibility'] == 'PUBLIC':
            report['exempt'].append(name)
            continue
        chosen = newest_ref(paths, info['default_branch'])
        if chosen is None:
            report['errors'].append({'repository': name,
                                     'problem': 'no local copy of ' + info['default_branch'] + ', skipped'})
            continue
        path, revision, stamp = chosen
        committed = dt.datetime.fromtimestamp(stamp, dt.timezone.utc).date().isoformat()
        report['checked'].append({'repository': name, 'branch': info['default_branch'],
                                  'revision': revision, 'committed': committed, 'checkout': str(path)})
        # The tool never fetches. Compare with GitHub so a stale local copy is visible.
        try:
            remote = command([gh, 'api', 'repos/' + name + '/commits/' + info['default_branch'],
                              '--jq', '.sha']).strip()
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
            report['stale'].append({'repository': name, 'problem': 'freshness unknown: ' + str(exc)})
        else:
            if remote != revision:
                report['stale'].append({'repository': name, 'problem': 'local ' + info['default_branch']
                                        + ' ' + revision[:12] + ' differs from GitHub ' + remote[:12]
                                        + '; fetch to refresh these results'})
        try:
            listed = git(path, 'ls-tree', '-z', '--name-only', revision, '.github/workflows/').split('\0')
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
            report['errors'].append({'repository': name, 'problem': 'cannot list workflows: ' + str(exc)})
            continue
        for file in sorted(item for item in listed if item.endswith(('.yml', '.yaml'))):
            try:
                problems = check_workflow(git(path, 'cat-file', 'blob', revision + ':' + file), owner)
            except ParseError as exc:
                report['errors'].append({'repository': name, 'file': file, 'problem': 'unreadable: ' + str(exc)})
                continue
            except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
                report['errors'].append({'repository': name, 'file': file, 'problem': str(exc)})
                continue
            for problem in problems:
                report['findings'].append({'repository': name, 'file': file, 'problem': problem})
    write_cache(cache_path, cache)
    return report


def exit_code(report):
    return 1 if report['findings'] else 2 if report['errors'] else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT,
                        help='directory holding Apps/*, Website/*, and BorrowedFire checkouts')
    parser.add_argument('--cache', type=Path, default=DEFAULT_CACHE, help='visibility cache file')
    parser.add_argument('--owner', default=DEFAULT_OWNER, help='GitHub owner whose repositories are checked')
    parser.add_argument('--gh', default='gh', help='GitHub CLI executable')
    parser.add_argument('--json', action='store_true', help='print one JSON report')
    args = parser.parse_args(argv)
    report = lint(args.root, args.cache, args.gh, args.owner)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for finding in report['findings']:
            print(finding['repository'] + ' ' + finding['file'] + ': ' + finding['problem'])
        for error in report['errors']:
            where = ' '.join(part for part in (error.get('repository'), error.get('file')) if part)
            print('error: ' + (where + ': ' if where else '') + error['problem'], file=sys.stderr)
        for stale in report['stale']:
            print('stale: ' + stale['repository'] + ': ' + stale['problem'], file=sys.stderr)
        if not report['findings'] and not report['errors']:
            print('clean: ' + str(len(report['checked'])) + ' private repositories checked')
    return exit_code(report)


if __name__ == '__main__':
    raise SystemExit(main())
