"""Borrowed Fire secret guard.

Keeps secret values out of agent transcripts. Tool output is the transcript: whatever a command
prints, the model reads, the session stores, and the owner's devices sync.

Modes (run through the `secret-guard` launcher, which fails closed when Python is unavailable):

  pre       PreToolUse hook (Claude Code and Codex). Reads the hook JSON on stdin and exits 2 with
            a reason on stderr when the tool call would print a secret.
  post      PostToolUse hook (Claude Code). Redacts well-known credential formats from the tool's
            output before the model sees it. A backstop for what `pre` cannot predict.
  run       The `bf-secret` wrapper. Reads secrets and hands them to one command through its
            environment, stdin, or a private temporary file, never to the terminal.
  register / unregister
            Add or remove this guard's entries in a harness hook file, once, keeping every
            other entry intact. Used by install.sh.

The `pre` check parses shell syntax instead of matching text, so a command that only mentions a
secret command (a commit message, a heredoc, a grep pattern) passes, and quoting or wrappers do
not hide a real call. It cannot follow indirection it cannot see: scripts, interpreters, aliases,
and variables that build command names. The `post` redactor and the written rule cover those.
"""

import base64
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading

BLOCK_HELP = (
    "Tool output is the transcript: never print a secret or any part, prefix, slice or encoding "
    "of one. Give a secret to the command that needs it with bf-secret, for "
    "example: bf-secret --env TOKEN=op://Vault/Item/field -- some-command. "
    "List item titles with 'op item list'. Check a secret by the consumer's exit code, never by "
    "looking at it. If this text only mentions a command (commit or PR prose), pass it from a file "
    "with -F or --body-file."
)


class Block(Exception):
    """The tool call would expose a secret."""


class ParseError(Exception):
    """The command is not shell syntax this guard can read."""


# ---------------------------------------------------------------------------------------------
# Shell parsing: just enough structure to know which words are commands, what feeds what, and
# where each command's output ends up.
# ---------------------------------------------------------------------------------------------

class Word:
    def __init__(self):
        self.text = ''           # literal text with quotes removed; substitutions become '\0'
        self.subs = []           # [(kind, Seq)] kind: '$(' '`' '<(' '>('
        self.refs = []           # [(name, op)] op: '' plain, '#' length, '+' alternate, 'x' other
        self.quoted = False

    def __repr__(self):
        return 'Word(%r)' % self.text


class Redir:
    def __init__(self, fd, op, target):
        self.fd, self.op, self.target = fd, op, target  # target: Word (or heredoc body Word)


class Cmd:
    def __init__(self):
        self.words, self.redirs = [], []


class Group:
    def __init__(self, body):
        self.body, self.redirs = body, []


META = set(';&|()<>\n')
RESERVED = {'!', 'if', 'then', 'elif', 'else', 'fi', 'do', 'done', 'while', 'until', 'time',
            'case', 'esac', 'in', 'function', 'coproc'}


class Parser:
    def __init__(self, text):
        self.s, self.i = text, 0
        self.heredocs = []   # pending [(Redir, delimiter, strip_tabs, quoted)]

    def peek(self, n=0):
        j = self.i + n
        return self.s[j] if j < len(self.s) else ''

    def parse(self):
        seq = self.seq(closer=None)
        if self.i < len(self.s):
            raise ParseError('unexpected ' + repr(self.s[self.i]))
        return seq

    def skip_blank(self):
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in ' \t':
                self.i += 1
            elif c == '\\' and self.peek(1) == '\n':
                self.i += 2
            else:
                break

    def read_heredocs(self):
        for redir, delim, strip, quoted in self.heredocs:
            lines = []
            while self.i < len(self.s):
                end = self.s.find('\n', self.i)
                line = self.s[self.i:] if end < 0 else self.s[self.i:end]
                self.i = len(self.s) if end < 0 else end + 1
                if (line.lstrip('\t') if strip else line) == delim:
                    break
                lines.append(line)
            body = '\n'.join(lines)
            if quoted:
                redir.target = Word()
                redir.target.text = body
            else:
                redir.target = Parser(body).dquote_body()
        self.heredocs = []

    def seq(self, closer):
        """Parse a list of pipelines until `closer` (')', '}', '`' or None for end of text)."""
        pipelines, stages = [], []
        while True:
            self.skip_blank()
            c = self.peek()
            if c == '':
                break
            if c == '#':
                while self.i < len(self.s) and self.s[self.i] != '\n':
                    self.i += 1
                continue
            if c == '\n':
                self.i += 1
                self.read_heredocs()
                if stages:
                    pipelines.append(stages)
                    stages = []
                continue
            if closer == ')' and c == ')':
                break
            if c == ')' and closer != ')':
                # A case pattern like 'a)' or stray text: not a command boundary we model.
                self.i += 1
                continue
            if c in ';&':
                self.i += 1
                while self.peek() and self.peek() in ';&':
                    self.i += 1
                if stages:
                    pipelines.append(stages)
                    stages = []
                continue
            if c == '|':
                self.i += 1
                if self.peek() == '|':
                    self.i += 1
                    if stages:
                        pipelines.append(stages)
                        stages = []
                elif self.peek() == '&':
                    self.i += 1
                continue
            if closer == '}' and c == '}' and self.word_ends(self.i + 1):
                break
            stages.append(self.stage(closer))
        if stages:
            pipelines.append(stages)
        return pipelines

    def word_ends(self, j):
        return j >= len(self.s) or self.s[j] in ' \t\n;&|)'

    def stage(self, closer):
        c = self.peek()
        if c == '(' and self.peek(1) == '(':
            node = Cmd()
            marker = Word()
            marker.text = '(('
            node.words = [marker, self.skip_arith(2)]
            self.redirections(node)
            return node
        if c == '(':
            self.i += 1
            node = Group(self.seq(')'))
            if self.peek() != ')':
                raise ParseError('unclosed (')
            self.i += 1
            self.redirections(node)
            return node
        if c == '{' and self.word_ends(self.i + 1):
            self.i += 1
            node = Group(self.seq('}'))
            if self.peek() != '}':
                raise ParseError('unclosed {')
            self.i += 1
            self.redirections(node)
            return node
        return self.command(closer)

    def redirections(self, node):
        while True:
            self.skip_blank()
            if not self.try_redirect(node, None):
                return

    def try_redirect(self, node, fd):
        s, i = self.s, self.i
        for op in ('&>>', '&>', '<<<', '<<-', '<<', '<>', '>>', '>|', '>&', '<&', '>', '<'):
            if s.startswith(op, i):
                self.i = i + len(op)
                self.skip_blank()
                if op in ('<<', '<<-'):
                    word = self.word()
                    redir = Redir(fd, op, Word())
                    self.heredocs.append((redir, word.text, op == '<<-', word.quoted))
                else:
                    redir = Redir(fd, op, self.word())
                node.redirs.append(redir)
                return True
        return False

    def command(self, closer):
        cmd = Cmd()
        while True:
            self.skip_blank()
            c = self.peek()
            if c == '' or c in ';&|\n' and not (c == '&' and self.peek(1) == '>'):
                break
            if c == ')':
                break
            if c == '}' and closer == '}' and self.word_ends(self.i + 1) and cmd.words:
                break
            if c == '#':
                break   # a comment: '#' that starts a word; seq() skips to the line end
            if c == '{' and self.word_ends(self.i + 1) and cmd.words and \
                    cmd.words[0].text == 'function':
                break
            if c == '(':
                if self.peek(1) == '(':                  # for (( ... )) arithmetic
                    cmd.words.append(self.skip_arith(2))
                    continue
                if cmd.words and self.peek(1) == ')':   # function definition: name()
                    self.i += 2
                    break
                if cmd.words and cmd.words[-1].text.endswith('='):
                    # Array assignment a=( ... ): read it as plain words.
                    self.i += 1
                    while True:
                        while self.peek() and self.peek() in ' \t\n':
                            self.i += 1
                        if self.peek() in ('', ')'):
                            break
                        cmd.words.append(self.word())
                    self.expect(')')
                    continue
                if cmd.words:
                    raise ParseError('unexpected (')
                break
            if cmd.words and len(cmd.words) == 1 and cmd.words[0].text == '[[' and \
                    not cmd.words[0].quoted:
                # A [[ test ]] can hold regex parentheses and '|'; it runs nothing.
                end = self.s.find(']]', self.i)
                if end < 0:
                    raise ParseError('unclosed [[')
                # Keep any $( ) inside the test visible to the analyzer. Text that does not
                # parse raises, so an early ']]' inside $( ) cannot hide a command.
                cmd.words.append(Parser(self.s[self.i:end]).dquote_body())
                self.i = end + 2
                continue
            if c in '<>' or (c == '&' and self.peek(1) == '>'):
                if c in '<>' and self.peek(1) == '(':
                    cmd.words.append(self.word())
                    continue
                self.try_redirect(cmd, None)
                continue
            m = re.match(r'\d+(?=[<>])', self.s[self.i:])
            if m:
                self.i += len(m.group())
                self.try_redirect(cmd, int(m.group()))
                continue
            cmd.words.append(self.word())
        return cmd

    def skip_arith(self, opened):
        """Read past (( ... )) and return a word holding any $( ) or backticks inside it,
        because arithmetic still runs command substitutions."""
        depth = opened
        self.i += opened
        start = self.i
        while self.i < len(self.s) and depth:
            c = self.s[self.i]
            depth += 1 if c == '(' else -1 if c == ')' else 0
            self.i += 1
        if depth:
            raise ParseError('unclosed ((')
        inner = self.s[start:self.i - opened]
        if '$(' in inner or '`' in inner:
            return Parser(inner).dquote_body()
        return Word()

    def word(self):
        w = Word()
        start = self.i
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in ' \t\n;&|)':
                break
            if c in '<>':
                if self.peek(1) == '(' and self.i == start:
                    self.i += 2
                    w.subs.append(('<(' if c == '<' else '>(', self.seq(')')))
                    self.expect(')')
                    w.text += '\0'
                    continue
                break
            if c == '(':
                break
            if c == '\\':
                if self.peek(1) == '\n':
                    self.i += 2
                    continue
                w.text += self.peek(1)
                self.i += 2
                continue
            if c == "'":
                end = self.s.find("'", self.i + 1)
                if end < 0:
                    raise ParseError('unclosed quote')
                w.text += self.s[self.i + 1:end]
                w.quoted = True
                self.i = end + 1
                continue
            if c == '"':
                self.i += 1
                self.dquote(w)
                w.quoted = True
                continue
            if c == '$' and self.peek(1) == "'":
                self.i += 1
                end = self.i + 1
                while end < len(self.s) and self.s[end] != "'":
                    end += 2 if self.s[end] == '\\' else 1
                if end >= len(self.s):
                    raise ParseError('unclosed quote')
                w.text += self.s[self.i + 1:end]
                w.quoted = True
                self.i = end + 1
                continue
            if c in '$`':
                self.dollar(w)
                continue
            w.text += c
            self.i += 1
        return w

    def expect(self, ch):
        if self.peek() != ch:
            raise ParseError('expected ' + ch)
        self.i += 1

    def dquote(self, w):
        while True:
            if self.i >= len(self.s):
                raise ParseError('unclosed double quote')
            c = self.s[self.i]
            if c == '"':
                self.i += 1
                return
            if c == '\\':
                nxt = self.peek(1)
                if nxt == '\n':
                    self.i += 2
                    continue
                w.text += nxt if nxt in '"\\$`' else '\\' + nxt
                self.i += 2
                continue
            if c in '$`':
                self.dollar(w)
                continue
            w.text += c
            self.i += 1

    def dquote_body(self):
        """Parse heredoc text as if double-quoted, without a closing quote."""
        w = Word()
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == '\\' and self.peek(1) and self.peek(1) in '$`\\':
                w.text += self.peek(1)
                self.i += 2
            elif c in '$`':
                self.dollar(w)
            else:
                w.text += c
                self.i += 1
        return w

    def dollar(self, w):
        s = self.s
        if s[self.i] == '`':
            j, inner = self.i + 1, ''
            while j < len(s) and s[j] != '`':
                if s[j] == '\\' and j + 1 < len(s):
                    inner += s[j + 1]
                    j += 2
                else:
                    inner += s[j]
                    j += 1
            if j >= len(s):
                raise ParseError('unclosed backtick')
            self.i = j + 1
            w.subs.append(('`', Parser(inner).parse()))
            w.text += '\0'
            return
        nxt = self.peek(1)
        if nxt == '(' and self.peek(2) == '(':
            self.i += 1
            w.subs.extend(self.skip_arith(2).subs)
            w.text += '0'
            return
        if nxt == '(':
            self.i += 2
            w.subs.append(('$(', self.seq(')')))
            self.expect(')')
            w.text += '\0'
            return
        if nxt == '{':
            self.i += 2
            depth, start = 1, self.i
            while self.i < len(s) and depth:
                if s.startswith('${', self.i) or s.startswith('$(', self.i):
                    inner = Word()
                    self.dollar(inner)
                    w.subs.extend(inner.subs)
                    w.refs.extend(inner.refs)
                    continue
                if s[self.i] == '\\':
                    self.i += 2
                    continue
                depth += {'{': 1, '}': -1}.get(s[self.i], 0)
                self.i += 1
            if depth:
                raise ParseError('unclosed ${')
            expr = s[start:self.i - 1]
            m = re.match(r'(#?)(!?)([A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])(.*)$', expr, re.S)
            if m:
                length, _, name, rest = m.groups()
                if length and not m.group(2):
                    op = '#'
                elif rest[:2] in (':+',) or rest[:1] == '+':
                    op = '+'
                elif rest:
                    op = 'x'
                else:
                    op = ''
                w.refs.append((name, op))
                w.text += '$' + name
            return
        m = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])', s[self.i:])
        if m:
            w.refs.append((m.group(1), ''))
            w.text += m.group()
            self.i += len(m.group())
            return
        w.text += '$'
        self.i += 1


def parse_shell(text):
    return Parser(text).parse()


# ---------------------------------------------------------------------------------------------
# Policy
# ---------------------------------------------------------------------------------------------

# Commands that copy their input (stdin or a file argument) to stdout.
PRINTERS = {
    'cat', 'bat', 'batcat', 'head', 'tail', 'less', 'more', 'most', 'strings', 'base64', 'base32',
    'xxd', 'od', 'hexdump', 'nl', 'tac', 'rev', 'fold', 'cut', 'tr', 'sed', 'gsed', 'awk', 'gawk',
    'jq', 'yq', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'sort', 'uniq', 'column', 'paste', 'fmt',
    'pr', 'expand', 'tee', 'openssl', 'plutil', 'iconv', 'dd', 'diff', 'colordiff', 'vis',
    'unvis',
}
# Search tools that print nothing of the input with these flags.
QUIET_SEARCH = {'-q', '--quiet', '--silent', '-l', '--files-with-matches', '-L',
                '--files-without-match', '-c', '--count'}
SEARCHERS = {'grep', 'egrep', 'fgrep', 'rg', 'ag'}
# Options that take the next word as their value, per tool. A wrong entry here makes the guard
# skip the pattern and miss a credential file, so each list holds only options documented to
# take a separate value.
_GREP_VALUES = {'-A', '-B', '-C', '-m', '-d', '-D', '--max-count', '--context',
                '--after-context', '--before-context', '--binary-files', '--devices',
                '--directories'}
SEARCH_VALUE_OPTIONS = {
    'grep': _GREP_VALUES, 'egrep': _GREP_VALUES, 'fgrep': _GREP_VALUES,
    'rg': {'-A', '-B', '-C', '-m', '-g', '-t', '-T', '-M', '-j', '-E', '-r', '--glob',
           '--iglob', '--type', '--type-not', '--max-count', '--context', '--after-context',
           '--before-context', '--max-columns', '--threads', '--replace', '--color',
           '--colors', '--sort', '--sortr', '--encoding', '--type-add', '--max-depth',
           '--max-filesize', '--path-separator', '--pre', '--pre-glob'},
    'ag': {'-A', '-B', '-C', '-m', '-G', '-g', '--context', '--after', '--before',
           '--max-count', '--file-search-regex', '--ignore', '--ignore-dir', '--depth',
           '--pager', '--path-to-ignore', '--workers'},
}


def search_files(prog, args):
    """The file operands of grep, rg or ag: everything but options and the search pattern."""
    value_options = SEARCH_VALUE_OPTIONS[prog]
    operands, pattern_given, i = [], False, 0
    while i < len(args):
        a = args[i]
        if a == '--':
            operands += args[i + 1:]
            break
        if a in ('-e', '--regexp', '-f', '--file'):
            pattern_given = True
            i += 2
            continue
        if a.startswith(('--regexp=', '--file=')):
            pattern_given = True
        elif a.startswith('-') and a != '-':
            i += 2 if a in value_options else 1
            continue
        else:
            operands.append(a)
        i += 1
    return operands if pattern_given else operands[1:]


def flag_on(flags, name):
    """True when a boolean flag is set, as --name or --name=<true value>."""
    for flag in flags:
        if flag == name:
            return True
        if flag.startswith(name + '=') and flag.split('=', 1)[1].lower() not in ('false', '0'):
            return True
    return False
# Commands that print their arguments.
ARG_PRINTERS = {'echo', 'printf', 'print', 'say'}
SHELLS = {'sh', 'bash', 'zsh', 'dash', 'ksh', 'fish', 'csh', 'tcsh'}
INTERPRETERS = {'python', 'python2', 'python3', 'node', 'nodejs', 'ruby', 'perl', 'php', 'lua',
                'osascript', 'deno', 'bun', 'tclsh', 'expect', 'pwsh'}
WRAPPERS = {'sudo', 'env', 'command', 'builtin', 'exec', 'nohup', 'time', 'nice', 'timeout',
            'gtimeout', 'caffeinate', 'xargs', 'stdbuf', 'noglob', 'nocorrect', 'doas', 'chronic'}
# Children a secret wrapper must refuse: anything that prints, or runs arbitrary code.
DENIED_CHILDREN = (PRINTERS | ARG_PRINTERS | SHELLS | INTERPRETERS | WRAPPERS
                   | {'printenv', 'set', 'export', 'declare', 'typeset', 'eval', 'op',
                      'op-unattended', 'security', 'script', 'ps', 'launchctl', 'bf-secret'})

TERMINAL_TARGETS = {'/dev/stdout', '/dev/stderr', '/dev/tty', '/dev/fd/1', '/dev/fd/2',
                    '/dev/console'}
SECRET_NAME = re.compile(
    r'(?:^|_)(?:TOKEN|SECRET|PASSWORD|PASSWD|PASSPHRASE|API_?KEY|PRIVATE_KEY|ACCESS_KEY'
    r'|SECRET_KEY|SERVICE_ROLE_KEY|SERVICE_KEY|CREDENTIALS?|AUTH|DATABASE_URL|DB_URL)$')
ENV_DUMP_CODE = re.compile(
    r'print\s*\(\s*(?:dict\s*\(\s*)?os\.environ\s*\)?\s*\)|console\.log\s*\(\s*process\.env\s*\)'
    r'|JSON\.stringify\s*\(\s*process\.env|(?:puts|p|pp)\s+ENV\b|print\s+%ENV')
OP_GLOBAL_WITH_VALUE = {'--account', '--config', '--session', '--encoding', '--format', '--cache'}
OP_ALIASES = {'items': 'item', 'documents': 'document', 'vaults': 'vault', 'accounts': 'account',
              'users': 'user', 'groups': 'group'}
OP_ALLOWED = {
    (), ('--version',), ('-v',), ('--help',), ('-h',), ('help',), ('whoami',), ('signout',),
    ('update',), ('completion',),
    ('account', 'list'), ('account', 'get'), ('account', 'forget'),
    ('vault', 'list'), ('vault', 'get'), ('user', 'list'), ('user', 'get'),
    ('group', 'list'), ('group', 'get'), ('item', 'list'), ('item', 'template'),
    ('item', 'delete'), ('document', 'list'), ('document', 'delete'), ('plugin', 'list'),
    ('plugin', 'inspect'),
}
# op commands whose output carries secret values; allowed only when written to a file.
OP_TO_FILE_ONLY = {('read',), ('inject',), ('document', 'get'), ('item', 'create'),
                   ('item', 'edit')}
SECURITY_WITH_VALUE = set('acCdDGjlprPstkTi')


def basename(text):
    return text.rstrip('/').rsplit('/', 1)[-1]


def is_secret_path(path):
    """True for files whose purpose is to hold credentials."""
    if not path or '\0' in path:
        return False
    if ':' in path and not path.startswith('/'):
        path = path.split(':', 1)[1]          # git show REV:path
    path = path.replace('\\', '/')
    name = basename(path)
    lowered = name.lower()
    if lowered.startswith('.env') and (len(lowered) == 4 or lowered[4] in '.*'):
        return not lowered.endswith(('.example', '.sample', '.template', '.dist', '.defaults',
                                     '.schema', '.md', '.ts', '.js', '.mjs', '.cjs', '.py',
                                     '.rb', '.go', '.swift', '.kt', '.java', '.rs'))
    if lowered in {'.netrc', '_netrc', '.npmrc', '.pypirc', '.git-credentials', '.pgpass',
                   '.my.cnf', 'credentials.json', '.credentials.json', 'access-token'}:
        return lowered != 'credentials.json' or '/.' in path or path.startswith('.')
    if re.fullmatch(r'id_(rsa|dsa|ecdsa|ed25519)(_sk)?', lowered):
        return True
    if re.search(r'\.(p8|p12|pfx|jks|keystore|mobileprovision-key)$', lowered):
        return True
    if re.search(r'(private|secret).*\.(pem|key|json)$', lowered) or re.search(
            r'-firebase-adminsdk-.*\.json$', lowered) or re.search(r'^authkey_.*$', lowered):
        return True
    for suffix in ('.aws/credentials', '.codex/auth.json', 'gh/hosts.yml', '.docker/config.json',
                   '.kube/config', '.supabase/access-token', 'op/config'):
        if path.endswith(suffix):
            return True
    return lowered.endswith('.pem') and not re.search(r'cert|chain|pub|bundle|^ca[-_.]', lowered)


class Analyzer:
    """Walks parsed shell and raises Block when a secret would reach the transcript."""

    def __init__(self):
        self.tainted = set()
        self.xtrace = False

    def ref_secret(self, name, op):
        if op in ('#', '+'):
            return False
        return name in self.tainted or bool(SECRET_NAME.search(name))

    def word_secret_refs(self, word):
        return any(self.ref_secret(n, op) for n, op in word.refs)

    # -- output routing -------------------------------------------------------------------

    def stdout_route(self, node):
        """Where stdout ends up after the node's redirections, applied in order: 'file',
        'terminal', or None when it still goes to the pipe or caller. Descriptors are followed
        through duplications such as 3>&1 >&3; an unknown descriptor counts as the terminal."""
        fds = {1: None, 2: 'terminal'}
        for r in node.redirs:
            target = r.target.text if r.target is not None else ''
            if '\0' in target:
                target = '/dev/stdout'   # >(command): treat the command's output as printed
            dest = 'terminal' if target in TERMINAL_TARGETS else 'file'
            if r.op in ('&>', '&>>'):
                fds[1] = fds[2] = dest
            elif r.op in ('>', '>>', '>|'):
                fds[1 if r.fd is None else r.fd] = dest
            elif r.op == '>&':
                fd = 1 if r.fd is None else r.fd
                if target.isdigit():
                    fds[fd] = fds.get(int(target), 'terminal')
                else:
                    fds[fd] = 'file' if target == '-' else dest
        return fds[1]

    def stdin_secret(self, node):
        for r in node.redirs:
            if r.op == '<' and r.fd in (None, 0) and is_secret_path(r.target.text):
                return True
            if r.op in ('<<<', '<<', '<<-') and (self.word_secret_refs(r.target)
                                                 or self.subs_secret(r.target, 'arg')):
                return True
        return False

    def subs_secret(self, word, use):
        """Analyze substitutions inside a word; True if one yields a secret into the word."""
        found = False
        for kind, seq in word.subs:
            if kind == '>(':
                self.seq(seq, 'terminal')
                continue
            if self.seq(seq, 'captured'):
                found = True
        return found

    # -- structure -------------------------------------------------------------------------

    def seq(self, seq, context, stdin=False):
        """Return True if secret output leaves the sequence through a captured context."""
        emitted = False
        for pipeline in seq:
            carry = stdin
            for stage in pipeline:
                carry = self.stage(stage, carry)
                route = self.stdout_route(stage)
                if route == 'file':
                    carry = False
                elif route == 'terminal' and carry:
                    raise Block('a secret would be written to the terminal')
            if carry:
                if context == 'terminal':
                    raise Block('a secret would be printed to the terminal')
                emitted = True
        return emitted

    def stage(self, node, stdin):
        stdin = stdin or self.stdin_secret(node)
        if isinstance(node, Group):
            return self.seq(node.body, 'captured', stdin)
        return self.command(node, stdin)

    # -- commands --------------------------------------------------------------------------

    def command(self, cmd, stdin):
        words = list(cmd.words)
        # Substitutions run first, whatever the command is.
        sub_secret = [self.subs_secret(w, 'arg') for w in words]
        for r in cmd.redirs:
            if r.target is not None:
                self.subs_secret(r.target, 'arg')

        # Shell tracing prints every word after expansion, assignments included.
        if self.xtrace and (any(sub_secret) or any(self.word_secret_refs(w) for w in words)):
            raise Block('shell tracing (set -x) would print a secret')

        # Leading assignments: NAME=value taints NAME when value carries a secret.
        k = 0
        assigned = False
        while k < len(words) and re.match(r'[A-Za-z_][A-Za-z0-9_]*\+?=', words[k].text):
            name = words[k].text.split('=', 1)[0].rstrip('+')
            if sub_secret[k] or self.word_secret_refs(words[k]):
                self.tainted.add(name)
            assigned = True
            k += 1
        words, sub_secret = words[k:], sub_secret[k:]
        while words and words[0].text in RESERVED and not words[0].quoted:
            words, sub_secret = words[1:], sub_secret[1:]
        if not words:
            return False if assigned else stdin

        args = [w.text for w in words]
        prog = basename(args[0])

        # Declarations that assign: export/local/declare/typeset/readonly NAME=value.
        if prog in ('export', 'local', 'declare', 'typeset', 'readonly'):
            names = [a for a in args[1:] if not a.startswith('-')]
            flags = [a for a in args[1:] if a.startswith('-')]
            if not names and (prog != 'local'):
                if not flags or any(set(f[1:]) & set('px') for f in flags) or prog == 'typeset':
                    return True   # prints every (exported) variable
            for i, a in enumerate(args[1:], 1):
                if '=' in a:
                    name = a.split('=', 1)[0]
                    if sub_secret[i] or self.word_secret_refs(words[i]):
                        self.tainted.add(name)
                elif prog in ('declare', 'typeset') and any('p' in f for f in flags) and \
                        self.ref_secret(a, ''):
                    return True
            return False

        if prog == 'set':
            rest = args[1:]
            if not rest:
                return True    # prints every variable
            for a in rest:
                if re.fullmatch(r'-[a-zA-Z]*x[a-zA-Z]*', a):
                    self.xtrace = True
                if a == 'xtrace' and '-o' in rest:
                    self.xtrace = True
                if re.fullmatch(r'\+[a-zA-Z]*x[a-zA-Z]*', a) or (a == 'xtrace' and '+o' in rest):
                    self.xtrace = False
            return False

        if prog == 'read':
            if stdin:
                for a in args[1:]:
                    if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', a):
                        self.tainted.add(a)
            return False

        return self.program(words, args, sub_secret, stdin, cmd)

    def program(self, words, args, sub_secret, stdin, cmd):
        prog = basename(args[0])

        # Unwrap command runners to find the real program.
        if prog in WRAPPERS:
            rest_words, rest_subs = self.unwrap(prog, words, sub_secret)
            if rest_words is None:
                if prog == 'env':
                    return True          # bare env prints the environment
                return stdin if prog == 'xargs' else False
            if prog == 'xargs' and not rest_words:
                return stdin
            if not rest_words:
                return False
            return self.program(rest_words, [w.text for w in rest_words], rest_subs, stdin, cmd)

        if prog in SHELLS or prog == 'eval':
            return self.shell(prog, words, args, stdin, cmd)
        if prog == 'ssh':
            return self.ssh(args, stdin)
        if prog in INTERPRETERS:
            code = ' '.join(args[1:])
            if ENV_DUMP_CODE.search(code):
                raise Block('this code prints the whole environment')
            return False

        if prog in ('op', 'op-unattended'):
            return self.op(args, cmd)
        if prog == 'security':
            return self.security(args, cmd)
        if prog == 'alias':
            for a in args[1:]:
                if '=' in a:
                    value = a.split('=', 1)[1]
                    first = basename(value.split()[0]) if value.split() else ''
                    if first in {'op', 'op-unattended', 'security'} | SHELLS | INTERPRETERS:
                        raise Block('an alias would hide a secret command from this guard')
                    analyze_script(value, self, False)
            return False
        if prog == 'bf-secret' or prog.startswith('with-'):
            self.wrapper_child(args)
            return False

        if prog == 'printenv':
            names = [a for a in args[1:] if not a.startswith('-')]
            return not names or any(self.ref_secret(n, '') for n in names)
        if prog == 'launchctl' and args[1:2] == ['getenv']:
            return any(self.ref_secret(n, '') for n in args[2:])
        if prog == 'ps' and self.ps_prints_environment(args[1:]):
            return True
        if prog == 'gh' and args[1:3] == ['auth', 'token']:
            return True
        if prog == 'gh' and args[1:3] == ['auth', 'status'] and (
                '-t' in args or '--show-token' in args):
            return True
        if prog == 'gcloud' and len(args) > 2 and args[1] == 'auth' and \
                args[2].startswith('print-') and args[2].endswith('token'):
            return True
        if prog == 'supabase' and 'api-keys' in args:
            return True
        if prog == 'aws' and args[1:3] == ['configure', 'export-credentials']:
            return True
        if prog == 'aws' and args[1:3] == ['configure', 'get'] and any(
                re.search(r'secret|session_token', a) for a in args[3:]):
            return True
        if prog == 'git':
            j = 1   # skip git's global options: git --no-pager diff, git -C dir show
            while j < len(args) and args[j].startswith('-'):
                j += 2 if args[j] in ('-C', '-c', '--git-dir', '--work-tree', '--namespace',
                                      '--config-env', '--exec-path') else 1
            sub, rest = (args[j], args[j + 1:]) if j < len(args) else ('', [])
            patch = any(a in ('-p', '-u') or a.startswith('--patch') for a in rest)
            if (sub in ('show', 'cat-file', 'diff') or (sub == 'log' and patch)) and \
                    any(is_secret_path(a) for a in rest):
                return True
            return False
        if prog == 'curl':
            verbose = any(a in ('-v', '--verbose', '--trace', '--trace-ascii') or
                          re.fullmatch(r'-[a-zA-Z]*v[a-zA-Z]*', a) for a in args[1:])
            secret_arg = any(self.word_secret_refs(w) for w in words[1:]) or any(sub_secret)
            auth = any(re.match(r'(?i)\s*(authorization|x-api-key|apikey)\s*:', a) or
                       a in ('-u', '--user', '--oauth2-bearer', '-n', '--netrc', '--netrc-file',
                             '--netrc-optional', '-K', '--config') or
                       a.startswith(('--netrc-file=', '--user=', '--config='))
                       for a in args[1:])
            if verbose and (secret_arg or auth):
                raise Block('curl verbose output would print the credential header')
            return False

        if prog in ARG_PRINTERS:
            return any(sub_secret[1:]) or any(self.word_secret_refs(w) for w in words[1:])

        if prog in PRINTERS:
            operands = args[1:]
            if prog in SEARCHERS:
                if any(a in QUIET_SEARCH or re.fullmatch(r'-[a-zA-Z]*[qlLc][a-zA-Z]*', a)
                       for a in operands):
                    return False
                operands = search_files(prog, operands)
            if prog == 'tee' and stdin and any(a in TERMINAL_TARGETS or '\0' in a
                                               for a in operands):
                raise Block('tee would copy a secret to the terminal')
            file_secret = any(is_secret_path(a) for a in operands) or any(
                kind == '<(' and self.seq(seq, 'captured') for w in words[1:]
                for kind, seq in w.subs)
            if prog == 'dd':
                file_secret = any(a.startswith('if=') and is_secret_path(a[3:]) for a in args)
            return stdin or file_secret
        return False

    @staticmethod
    def ps_prints_environment(args):
        """BSD-style 'e' in the first option word, or -E/-e style clusters with E."""
        value_options = set('oOpuUgGtMN')
        for index, a in enumerate(args):
            if index == 0 and not a.startswith('-') and 'e' in a:
                return True
            if a.startswith('-') and not a.startswith('--'):
                for ch in a[1:]:
                    if ch == 'E':
                        return True
                    if ch in value_options:
                        break
        return False

    def unwrap(self, prog, words, subs):
        """Skip a runner's own options; return the wrapped command words, or None if none."""
        i = 1
        takes_value = {
            'sudo': {'-u', '-g', '-h', '-p', '-C', '-D', '-r', '-t', '-U'},
            'env': {'-u', '-C', '-S', '-P'},
            'nice': {'-n'}, 'stdbuf': {'-i', '-o', '-e'},
            'xargs': {'-I', '-n', '-L', '-P', '-s', '-d', '-E', '-J', '-R', '-S', '-a'},
            'timeout': {'-s', '-k', '--signal', '--kill-after'},
            'gtimeout': {'-s', '-k', '--signal', '--kill-after'},
            'caffeinate': {'-t', '-w'}, 'exec': {'-a'},
        }.get(prog, set())
        while i < len(words):
            a = words[i].text
            if a == '--':
                i += 1
                break
            if prog == 'env' and re.match(r'[A-Za-z_][A-Za-z0-9_]*=', a):
                i += 1
                continue
            if a.startswith('-') and a != '-':
                i += 2 if a in takes_value else 1
                continue
            break
        if prog in ('timeout', 'gtimeout') and i < len(words):
            i += 1    # the duration
        if i >= len(words):
            return None, None
        return words[i:], subs[i:]

    def shell(self, prog, words, args, stdin, cmd):
        script = None
        trace = False
        if prog == 'eval':
            script = ' '.join(args[1:])
        else:
            # Shell options come first: clusters like -euo (each 'o' takes the next word as an
            # option name), long options like --norc, and +o. With -c, the first operand is
            # the script; without it, the first operand is a script file we cannot see.
            i, run_string, from_stdin = 1, False, False
            while i < len(args):
                a = args[i]
                if a == '--':
                    i += 1
                    break
                if a in ('--rcfile', '--init-file'):
                    i += 2
                    continue
                if a == '--command':            # fish
                    run_string = True
                    i += 1
                    continue
                if a.startswith('--'):
                    i += 1
                    continue
                if len(a) > 1 and a[0] in '-+':
                    i += 1
                    for ch in a[1:]:
                        if ch == 'c':
                            run_string = True
                        elif ch == 's':
                            from_stdin = True
                        elif ch == 'x' and a[0] == '-':
                            trace = True
                        elif ch in 'oO' and i < len(args):
                            if args[i] == 'xtrace' and a[0] == '-':
                                trace = True
                            i += 1
                    continue
                break
            if run_string and i < len(args):
                script = args[i]
            if script is None and not run_string and (from_stdin or i >= len(args)):
                for r in cmd.redirs:
                    if r.op in ('<<', '<<-', '<<<'):
                        script = r.target.text
        if script is None:
            return False
        return analyze_script(script, self, stdin, trace)

    def ssh(self, args, stdin):
        takes_value = set('bcDEeFIiJLlmOopQRSWw')
        i = 1
        while i < len(args):
            a = args[i]
            if a.startswith('-') and len(a) > 1:
                i += 2 if a[-1] in takes_value and len(a) == 2 else 1
                continue
            break
        remote = ' '.join(args[i + 1:])
        if not remote:
            return False
        return analyze_script(remote, self, stdin)

    def wrapper_child(self, args):
        i = 1
        if basename(args[0]) == 'bf-secret':
            while i < len(args) and args[i] != '--':
                i += 1
            i += 1
        child = args[i:] if i < len(args) else []
        if child and basename(child[0]) in DENIED_CHILDREN:
            raise Block('a secret wrapper would hand the secret to %s, which can print it'
                        % basename(child[0]))

    def op(self, args, cmd):
        rest = args[1:]
        words = []
        out_file = False
        i = 0
        flags = []
        while i < len(rest):
            a = rest[i]
            if a in OP_GLOBAL_WITH_VALUE or a in ('-o', '--out-file', '--vault', '--fields',
                                                  '--categories', '--tags', '--env-file',
                                                  '--file', '-i', '--in-file', '--title',
                                                  '--category', '--template'):
                if a in ('-o', '--out-file'):
                    out_file = i + 1 < len(rest) and rest[i + 1] not in TERMINAL_TARGETS \
                        and '\0' not in rest[i + 1]
                flags.append(a)
                i += 2
                continue
            if a.startswith('-'):
                if a.startswith('--out-file='):
                    target = a.split('=', 1)[1]
                    out_file = target not in TERMINAL_TARGETS and '\0' not in target
                flags.append(a)
                i += 1
                if a == '--':
                    break
                continue
            if len(words) < 2 and (not words or words[0] not in ('read', 'inject', 'run')):
                words.append(OP_ALIASES.get(a, a))
            i += 1
        key = tuple(words[:2]) if words[:1] not in (['read'], ['inject'], ['run']) \
            else tuple(words[:1])
        if flag_on(flags, '--reveal'):
            raise Block("'--reveal' prints concealed 1Password fields")
        if key == ('run',):
            if flag_on(flags, '--no-masking'):
                raise Block("'op run --no-masking' prints secret values")
            j = rest.index('--') + 1 if '--' in rest else len(rest)
            child = rest[j:]
            if child and basename(child[0]) in SHELLS | INTERPRETERS:
                raise Block("'op run' into a shell or interpreter can print unmasked values")
            return False
        if key in OP_ALLOWED or (len(key) == 2 and key[0] == 'item' and key[1] == 'template'):
            return False
        if key in OP_TO_FILE_ONLY:
            if out_file or self.stdout_route(cmd) == 'file':
                return False
            raise Block("'op %s' prints secret values; use bf-secret, or write to a file with "
                        "--out-file" % ' '.join(key))
        if key[:2] == ('item', 'get'):
            raise Block("'op item get' prints item fields, including secrets; use bf-secret "
                        "with an op://vault/item/field reference")
        raise Block("'op %s' is not on the list of 1Password commands that cannot print "
                    "secrets" % ' '.join(key))

    def security(self, args, cmd):
        rest = args[1:]
        i = 0
        while i < len(rest) and rest[i].startswith('-'):
            i += 1
        if i >= len(rest):
            return False
        sub, opts = rest[i], rest[i + 1:]
        letters = set()
        j = 0
        while j < len(opts):
            a = opts[j]
            if a.startswith('-') and not a.startswith('--') and len(a) > 1:
                for pos, ch in enumerate(a[1:]):
                    letters.add(ch)
                    if ch in SECURITY_WITH_VALUE:
                        if pos == len(a) - 2:
                            j += 1   # value is the next word
                        break        # rest of the cluster is the value
            j += 1
        if sub in ('find-generic-password', 'find-internet-password'):
            if 'g' in letters:
                raise Block("'security %s -g' prints the password" % sub)
            if 'w' in letters:
                if self.stdout_route(cmd) == 'file':
                    return False
                raise Block("'security %s -w' prints the password; use bf-secret with "
                            "keychain:SERVICE" % sub)
            return False
        if sub == 'dump-keychain' and 'd' in letters:
            raise Block("'security dump-keychain -d' prints every secret in the keychain")
        if sub == 'export' and not ({'o'} & letters or '--outfile' in opts):
            raise Block("'security export' without -o prints key material")
        return False


# Words that make an unreadable command worth stopping. Other unreadable commands pass, so
# unusual but harmless syntax does not block work.
GUARDED_WORDS = re.compile(
    r'\b(?:op|op-unattended|security|bf-secret|printenv|env|set|export|declare|typeset|eval|'
    r'gh|gcloud|supabase|aws|ssh|sh|bash|zsh|launchctl|ps|alias)\b|\.env|\.p8|\.netrc|'
    r'auth\.json|id_(?:rsa|ed25519|ecdsa)|TOKEN|SECRET|PASSWORD|KEY')


def analyze_script(text, parent, stdin, trace=False):
    """Analyze a nested script (sh -c, eval, ssh, alias) with the caller's variable state."""
    inner = Analyzer()
    inner.tainted = set(parent.tainted)
    inner.xtrace = parent.xtrace or trace
    text = text.replace('\0', '')
    try:
        tree = parse_shell(text)
    except ParseError as error:
        if GUARDED_WORDS.search(text):
            raise Block('the guard could not read this command (%s); simplify it' % error)
        return False
    return inner.seq(tree, 'captured', stdin)


def check_shell(command):
    if isinstance(command, list):
        import shlex
        command = shlex.join(str(part) for part in command)
    if not isinstance(command, str):
        raise Block('the command is not text')
    if 'decrypted_secrets' in command:
        raise Block('vault.decrypted_secrets returns plaintext secrets')
    try:
        tree = parse_shell(command)
    except ParseError as error:
        if GUARDED_WORDS.search(command):
            raise Block('the guard could not read this command (%s); simplify it' % error)
        return
    Analyzer().seq(tree, 'terminal')


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def check_pre(event):
    tool = str(event.get('tool_name') or '')
    data = event.get('tool_input')
    if not isinstance(data, dict):
        data = {}
    if tool == 'Read' or (not tool and 'file_path' in data):
        if is_secret_path(str(data.get('file_path', ''))):
            raise Block('this file holds credentials')
        return
    if tool == 'Grep':
        target = str(data.get('path', '')) + ' ' + str(data.get('glob', ''))
        if data.get('output_mode') == 'content' and any(
                is_secret_path(part) for part in target.split()):
            raise Block('this search would print lines from a credentials file')
        return
    if not tool.startswith('mcp__') and ('command' in data or 'cmd' in data):
        check_shell(data.get('command', data.get('cmd')))
        return
    for text in strings_in(data):
        if 'decrypted_secrets' in text:
            raise Block('vault.decrypted_secrets returns plaintext secrets')


# ---------------------------------------------------------------------------------------------
# Output redaction (PostToolUse)
# ---------------------------------------------------------------------------------------------

REDACTIONS = [
    ('private key', re.compile(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END [A-Z0-9 ]*'
                               r'PRIVATE KEY-----|\Z)', re.S)),
    ('Supabase token', re.compile(r'\bsbp_(?:oauth_|v0_)?[0-9a-f]{40}\b')),
    ('Supabase key', re.compile(r'\bsb_secret_[A-Za-z0-9_-]{16,}')),
    ('1Password token', re.compile(r'\bops_[A-Za-z0-9_-]{40,}')),
    ('GitHub token', re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})')),
    ('API key', re.compile(r'\bsk-(?:ant-|proj-|svcacct-)?[A-Za-z0-9_-]{32,}')),
    ('Stripe key', re.compile(r'\b(?:sk|rk)_live_[A-Za-z0-9]{16,}')),
    ('Slack token', re.compile(r'\bxox[abposr]-[A-Za-z0-9-]{10,}')),
    ('AWS secret', re.compile(r'(?i)(aws_secret_access_key\s*[=:]\s*)[A-Za-z0-9/+=]{40}')),
    ('JWT', re.compile(r'\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{16,}')),
    ('URL password', re.compile(r'(\b[a-z][a-z0-9+.-]*://[^\s:/@"\']+:)[^\s@/"\']+(@)')),
]


def redact_text(text):
    for label, pattern in REDACTIONS:
        if pattern.groups == 2:
            text = pattern.sub(lambda m: m.group(1) + '[REDACTED]' + m.group(2), text)
        elif pattern.groups == 1:
            text = pattern.sub(lambda m: m.group(1) + '[REDACTED %s]' % label, text)
        else:
            text = pattern.sub('[REDACTED %s]' % label, text)
    return text


def redact(value):
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        return {key: redact(item) for key, item in value.items()}
    return value


def run_post(event):
    response = event.get('tool_response')
    if response is None:
        return
    cleaned = redact(response)
    if cleaned != response:
        json.dump({'hookSpecificOutput': {
            'hookEventName': 'PostToolUse',
            'updatedToolOutput': cleaned,
            'additionalContext': 'The secret guard redacted credential values from this output. '
                                 'Do not try to recover them.',
        }}, sys.stdout)


# ---------------------------------------------------------------------------------------------
# bf-secret: hand a secret to one command without printing it
# ---------------------------------------------------------------------------------------------

USAGE = """usage: bf-secret [--env NAME=REF]... [--file NAME=REF]... [--stdin REF] -- COMMAND [ARG...]

Reads each secret and gives it only to COMMAND:
  --env NAME=REF    set environment variable NAME to the secret
  --file NAME=REF   write the secret to a private temporary file and set NAME to its path
  --stdin REF       write the secret to COMMAND's standard input
REF is op://vault/item/field or keychain:SERVICE (keychain:SERVICE#ACCOUNT for one account).
Secret values in COMMAND's output are replaced with [REDACTED]. Shells, interpreters and
commands that print their input are refused.
1Password reads use the command named in ~/.config/borrowedfire/secret-reader if present,
otherwise 'op'."""


def reader_command():
    root = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    path = os.path.join(root, 'borrowedfire', 'secret-reader')
    try:
        with open(path) as handle:
            line = handle.readline().strip()
            if line:
                return os.path.expanduser(line)
    except OSError:
        pass
    return 'op'


def read_secret(ref):
    if ref.startswith('op://'):
        argv = [reader_command(), 'read', '--no-newline', ref]
    elif ref.startswith('keychain:'):
        service, _, account = ref[len('keychain:'):].partition('#')
        if not service:
            raise SystemExit('bf-secret: keychain reference needs a service name')
        argv = ['/usr/bin/security', 'find-generic-password', '-s', service, '-w']
        if account:
            argv[3:3] = ['-a', account]
    else:
        raise SystemExit('bf-secret: unsupported reference (use op:// or keychain:)')
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit('bf-secret: could not read %s (%s)' % (ref, type(error).__name__))
    if result.returncode != 0:
        raise SystemExit('bf-secret: could not read %s (exit %d)' % (ref, result.returncode))
    value = result.stdout
    if ref.startswith('keychain:') and value.endswith(b'\n'):
        value = value[:-1]
    if not value:
        raise SystemExit('bf-secret: %s is empty' % ref)
    return value


def pump(source, sink, secrets):
    """Copy a stream, replacing every secret value even across read boundaries."""
    hold = max((len(s) for s in secrets), default=1) - 1
    buffer = b''
    while True:
        chunk = os.read(source, 65536)
        if chunk:
            buffer += chunk
        for secret in secrets:
            buffer = buffer.replace(secret, b'[REDACTED]')
        if not chunk:
            sink.write(buffer)
            sink.flush()
            return
        cut = len(buffer) - hold if hold > 0 else len(buffer)
        if cut > 0:
            sink.write(buffer[:cut])
            sink.flush()
            buffer = buffer[cut:]


def stop_on_signal(number, frame):
    raise SystemExit(128 + number)   # unwinds through finally, so temp files are removed


def run_wrapper(argv):
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop_on_signal)
    envs, files, stdin_ref = [], [], None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--':
            i += 1
            break
        if a in ('--env', '--file') and i + 1 < len(argv) and '=' in argv[i + 1]:
            name, ref = argv[i + 1].split('=', 1)
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
                raise SystemExit('bf-secret: invalid variable name %r' % name)
            (envs if a == '--env' else files).append((name, ref))
            i += 2
            continue
        if a == '--stdin' and i + 1 < len(argv) and stdin_ref is None:
            stdin_ref = argv[i + 1]
            i += 2
            continue
        if a in ('-h', '--help'):
            print(USAGE)
            return 0
        raise SystemExit(USAGE)
    child = argv[i:]
    if not child or not (envs or files or stdin_ref):
        raise SystemExit(USAGE)
    resolved = shutil.which(child[0]) or child[0]
    names = {basename(child[0]), basename(os.path.realpath(resolved))}
    if names & DENIED_CHILDREN or any(n.startswith(('python', 'with-')) for n in names):
        raise SystemExit('bf-secret: refusing to give a secret to %s: it can print it. Use the '
                         'program that consumes the secret directly.' % basename(child[0]))

    env = dict(os.environ)
    secrets = []
    temp_dir = None
    try:
        for name, ref in envs:
            value = read_secret(ref)
            secrets.append(value)
            env[name] = value.decode('utf-8', 'surrogateescape')
        if files:
            temp_dir = tempfile.mkdtemp(prefix='bf-secret-')
            os.chmod(temp_dir, 0o700)
            for name, ref in files:
                value = read_secret(ref)
                secrets.append(value)
                path = os.path.join(temp_dir, name)
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, 'wb') as handle:
                    handle.write(value)
                env[name] = path
        stdin_value = read_secret(stdin_ref) if stdin_ref else None
        if stdin_value is not None:
            secrets.append(stdin_value)
        variants = []
        for secret in secrets:
            variants += [secret, base64.b64encode(secret)]
        variants = sorted({v for v in variants if len(v) >= 4}, key=len, reverse=True)

        proc = subprocess.Popen(child, env=env,
                                stdin=subprocess.PIPE if stdin_value is not None else None,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        threads = [threading.Thread(target=pump, args=(proc.stdout.fileno(),
                                                       sys.stdout.buffer, variants)),
                   threading.Thread(target=pump, args=(proc.stderr.fileno(),
                                                       sys.stderr.buffer, variants))]
        for thread in threads:
            thread.start()
        if stdin_value is not None:
            try:
                proc.stdin.write(stdin_value)
                proc.stdin.close()
            except BrokenPipeError:
                pass
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, lambda number, frame: proc.send_signal(number))
        code = proc.wait()
        for thread in threads:
            thread.join()
        return code if code >= 0 else 128 - code
    except FileNotFoundError:
        raise SystemExit('bf-secret: command not found: %s' % child[0])
    finally:
        if temp_dir:
            shutil.rmtree(temp_dir, ignore_errors=True)


# ---------------------------------------------------------------------------------------------
# Hook registration (install.sh)
# ---------------------------------------------------------------------------------------------

CLAUDE_PRE_MATCHER = 'Bash|Read|Grep|mcp__.*'
CODEX_PRE_MATCHER = '^(Bash|mcp__.*)$'


def wanted_groups(kind, launcher):
    quoted = '"%s"' % launcher
    if kind == 'claude':
        return {
            'PreToolUse': {'matcher': CLAUDE_PRE_MATCHER, 'hooks': [{
                'type': 'command', 'command': quoted + ' pre', 'timeout': 15,
                'onFailure': 'block'}]},
            'PostToolUse': {'matcher': '*', 'hooks': [{
                'type': 'command', 'command': quoted + ' post', 'timeout': 15}]},
        }
    return {
        'PreToolUse': {'matcher': CODEX_PRE_MATCHER, 'hooks': [{
            'type': 'command', 'command': quoted + ' pre', 'timeout': 15}]},
    }


def strip_ours(hooks, launcher):
    for event in list(hooks):
        groups = hooks[event]
        if not isinstance(groups, list):
            continue
        kept = []
        for group in groups:
            if isinstance(group, dict) and isinstance(group.get('hooks'), list):
                group = dict(group)
                group['hooks'] = [h for h in group['hooks'] if not (
                    isinstance(h, dict) and launcher in str(h.get('command', '')))]
                if not group['hooks']:
                    continue
            kept.append(group)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]


def load_hook_file(path):
    try:
        with open(path) as handle:
            text = handle.read()
    except FileNotFoundError:
        return {}
    data = json.loads(text) if text.strip() else {}
    if not isinstance(data, dict) or not isinstance(data.get('hooks', {}), dict):
        raise SystemExit('secret-guard: %s is not a JSON object with a hooks object' % path)
    return data


def write_hook_file(path, data):
    path = os.path.realpath(path)   # a symlinked settings file stays a symlink
    directory = os.path.dirname(path) or '.'
    os.makedirs(directory, exist_ok=True)
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except FileNotFoundError:
        mode = 0o644
    fd, temp = tempfile.mkstemp(dir=directory, prefix='.secret-guard.')
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(data, handle, indent=2)
            handle.write('\n')
        os.chmod(temp, mode)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def register(kind, path, launcher, remove=False):
    if kind not in ('claude', 'codex'):
        raise SystemExit('secret-guard: unknown hook file kind %r' % kind)
    data = load_hook_file(path)
    before = json.dumps(data, sort_keys=True)
    hooks = data.setdefault('hooks', {})
    strip_ours(hooks, launcher)
    if not remove:
        for event, group in wanted_groups(kind, launcher).items():
            hooks.setdefault(event, []).append(group)
    if not hooks:
        del data['hooks']
    if json.dumps(data, sort_keys=True) != before and (data or os.path.exists(path)):
        write_hook_file(path, data)
    return 0


def registered(kind, path, launcher):
    """Exit 0 when the hook file holds exactly this guard's entries, once each."""
    data = load_hook_file(path)
    hooks = data.get('hooks', {})
    for event, group in wanted_groups(kind, launcher).items():
        found = [g for g in hooks.get(event, []) if isinstance(g, dict) and any(
            isinstance(h, dict) and launcher in str(h.get('command', ''))
            for h in g.get('hooks', []))]
        if found != [group]:
            return 1
    return 0


# ---------------------------------------------------------------------------------------------

CHECK_TIME_LIMIT = 10   # seconds; under the hook timeout, so a slow check blocks, never hangs


def out_of_time(number, frame):
    raise TimeoutError('the check took longer than %d seconds' % CHECK_TIME_LIMIT)


def main(argv):
    mode = argv[0] if argv else ''
    if mode in ('pre', 'post'):
        signal.signal(signal.SIGALRM, out_of_time)
        signal.alarm(CHECK_TIME_LIMIT)
    if mode == 'pre':
        try:
            event = json.loads(sys.stdin.read() or '{}')
            if not isinstance(event, dict):
                raise ValueError('hook input is not an object')
            check_pre(event)
        except Block as reason:
            sys.stderr.write('BLOCKED by the Borrowed Fire secret guard: %s. %s\n'
                             % (reason, BLOCK_HELP))
            return 2
        return 0
    if mode == 'post':
        try:
            event = json.loads(sys.stdin.read() or '{}')
            if isinstance(event, dict):
                run_post(event)
        except (ValueError, TimeoutError):
            pass
        return 0
    if mode == 'run':
        return run_wrapper(argv[1:])
    if mode in ('register', 'unregister') and len(argv) == 4:
        return register(argv[1], argv[2], argv[3], remove=mode == 'unregister')
    if mode == 'registered' and len(argv) == 4:
        return registered(argv[1], argv[2], argv[3])
    sys.stderr.write('usage: secret-guard pre|post|run|register|unregister|registered ...\n')
    return 64


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except KeyboardInterrupt:
        sys.exit(130)
    except BaseException as error:
        if sys.argv[1:2] == ['pre']:   # a guard that crashes must not let the call through
            sys.stderr.write('BLOCKED: the Borrowed Fire secret guard failed (%s); the call was '
                             'stopped to stay safe.\n' % type(error).__name__)
            sys.exit(2)
        sys.stderr.write('secret-guard: %s\n' % type(error).__name__)
        sys.exit(1)
