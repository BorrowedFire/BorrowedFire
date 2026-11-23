#!/usr/bin/env python3
"""Contracts for guard/: the PreToolUse secret check, output redaction, bf-secret, the
fail-closed launcher, and hook registration. No real secret store is touched: 1Password reads go
to a fake reader named in a temporary XDG config."""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / 'guard'
LAUNCHER = GUARD / 'secret-guard'

BLOCK = [
    # 1Password: item reads in every spelling, and the other commands that print values
    'op item get abc --format json',
    '~/.local/bin/op-unattended item get abc --vault V --format json | python3 -c "print(1)"',
    '/opt/homebrew/bin/op item get abc',
    'op --account me item get abc',
    'op item --vault V get abc',
    'op "item" \'get\' abc',
    'op item \\\nget abc',
    'command op item get abc',
    'sudo -u me op item get abc',
    'sh -c "op item get abc"',
    'bash -lc \'op item get abc && true\'',
    'eval "op item g""et abc"',
    'echo abc | xargs op item get',
    'echo get abc | xargs op item',
    'sub=get; op item $sub abc',
    'alias o=op; o item get abc',
    'f(){ op-unattended "$@"; }; f item get abc',
    'function f { op item get abc; }',
    'if true; then op item get abc; fi',
    'ssh host op item get abc',
    'bash <<EOF\nop item get abc\nEOF',
    'op item get abc --fields password | jq -r .value',
    'op read op://v/i/f',
    'op read op://v/i/f | cat',
    'op read op://v/i/f | head -c 18',
    'echo "$(op read op://v/i/f)"',
    'X=$(op read op://v/i/f); printf "%s" "$X" | consumer',
    'op read op://v/i/f > /dev/stderr',
    'op read op://v/i/f --out-file /dev/stdout',
    'echo "{{ op://v/i/f }}" | op inject',
    'op document get abc',
    'op run --no-masking -- printenv DB_PASSWORD',
    'op run -- sh -c "echo $DB_PASSWORD"',
    'op item edit abc --reveal',
    'op item create --category login password=x',
    'op signin',
    'op item share abc',
    # Keychain
    'security find-generic-password -s S -w',
    'security find-generic-password -w -s S',
    'security find-generic-password -ws S',
    'security find-generic-password -s S -g',
    '/usr/bin/security find-internet-password -s github.com -w',
    'security find-generic-password -s S -w | cat',
    'raw=$(security find-generic-password -s S -w); echo "${raw:0:18}"',
    'security dump-keychain -d login.keychain-db',
    'security export -k login.keychain-db -t identities',
    # Environment and named secret variables
    'env', 'make build && env', '(env)', 'env | sort', 'env | grep -i key',
    'printenv', 'printenv SUPABASE_ACCESS_TOKEN', 'echo $GITHUB_TOKEN',
    'echo "token: ${API_KEY}"', 'p=${DB_PASSWORD:0:4}; echo "$p"',
    'printf %s "$OP_SERVICE_ACCOUNT_TOKEN"', 'cat <<< "$SUPABASE_SERVICE_ROLE_KEY"',
    'cat <<EOF\n$GITHUB_TOKEN\nEOF',
    'set', 'set | grep TOKEN', 'export', 'export -p', 'declare -p', 'declare -x', 'typeset',
    'set -x; curl -H "Authorization: Bearer $API_TOKEN" https://example.com',
    'bash -x -c \'curl -H "x-api-key: $API_KEY" https://example.com\'',
    'curl -v -H "Authorization: Bearer $TOKEN" https://example.com',
    'curl -sv -u user:pass https://example.com',
    'launchctl getenv GITHUB_TOKEN', 'ps eww', 'ps auxe',
    'python3 -c "import os;print(dict(os.environ))"', 'node -e "console.log(process.env)"',
    # Credential files and CLI tokens
    'cat .env', 'cat .env.local', 'grep -r PASSWORD .env*', 'tail -n 3 config/.env.production',
    'cat ~/.netrc', 'base64 -i ~/keys/AuthKey_ABC.p8', 'cat server.pem', 'xxd id_ed25519',
    'cat ~/.codex/auth.json', 'cat ~/.claude/.credentials.json', 'cat ~/.config/gh/hosts.yml',
    'cat ~/.aws/credentials', 'cat ~/.supabase/access-token', 'head < .env',
    'cat .env | grep URL', 'git show HEAD:.env', 'git diff -- .env', 'dd if=.env',
    'gh auth token', 'gh auth status --show-token', 'gcloud auth print-access-token',
    'supabase projects api-keys --project-ref abc', 'aws configure export-credentials',
    'psql "$DB" -c "select * from vault.decrypted_secrets"',
    # Secret wrappers must not feed printers or shells
    'bf-secret --env T=op://v/i/f -- printenv T', 'bf-secret --env T=op://v/i/f -- sh -c "echo $T"',
    'with-cloud-token env', 'with-cloud-token python3 -c "import os"',
    # Unreadable commands that involve guarded words
    'op item get "unterminated',
]

ALLOW = [
    'ls -la', 'git status', 'npm test', 'make build', 'echo hello', 'cd /tmp && ls',
    # Prose and searches that only mention the commands
    'git commit -m "Hook blocks op item get and op read"',
    'cat > notes.md <<EOF\nNever run op item get in a session.\nEOF',
    "cat > notes.md <<'EOF'\nX=$(op read op://v/i/f)\nEOF",
    'grep -rn "op item get" docs/', 'rg "security find-generic-password -w" .',
    '# we used to op read here\nls', 'echo top read latency', 'npx shop item get 3',
    'gh pr create --title "Guard op read" --body-file body.md',
    # Safe 1Password and keychain commands
    'op whoami', 'op --version', 'op vault list', 'op item list --vault V --format json',
    'op item list --vault V --format json | jq -r ".[].title"', 'op item template get Login',
    'op read op://v/i/f > "$TMP/key"; chmod 600 "$TMP/key"',
    'op read --out-file key.p8 op://v/i/f', 'op read -o /tmp/k op://v/i/f',
    'op inject -i tpl.env -o .env.rendered', 'op document get abc --out-file doc.pdf',
    'op item create --category login --generate-password > /dev/null',
    'op run --env-file app.env -- npm start',
    'security find-generic-password -s S >/dev/null && echo yes',
    'security add-generic-password -s S -a A -w', 'security find-certificate -a -p',
    'security find-generic-password -s S -w > "$TMP/pw"',
    # Environment use that prints nothing secret
    'env FOO=1 make test', 'env -i PATH=/usr/bin make', 'env | grep -c PATH', 'env > /tmp/e',
    'true && env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version',
    'printenv PATH', 'echo "$HOME"', 'echo "$TMPDIR" "$XCODE"', 'cat "$TOKEN_FILE"',
    'echo "length ${#GITHUB_TOKEN}"', '[ -n "$GITHUB_TOKEN" ] && echo "have token"',
    'echo "${API_KEY:+set}"',
    'curl -H "Authorization: Bearer $TOKEN" https://example.com',
    'printf %s "$GITHUB_TOKEN" | gh auth login --with-token',
    'curl -v https://example.com', 'set -euo pipefail', 'set -x; make',
    'export PATH="$HOME/bin:$PATH"', 'declare -a items', 'ps aux', 'ps -ef',
    'gh auth token | docker login ghcr.io -u me --password-stdin',
    'gh auth status', 'python3 -c "import os; print(os.environ.get(\'HOME\'))"',
    # Credential files used without printing
    'source .env', 'cp .env .env.bak', 'ls ~/.ssh', 'cat .env.example', 'cat id_ed25519.pub',
    'cat cert.pem', 'grep -c KEY .env', 'grep -q KEY .env && echo found',
    'chmod 600 ~/keys/AuthKey_ABC.p8', 'base64 -i AuthKey_ABC.p8 | pbcopy',
    # Wrappers that hand secrets to consumers
    'bf-secret --env SUPABASE_ACCESS_TOKEN=op://v/i/f -- supabase db push',
    'bf-secret --stdin keychain:S -- docker login -u me --password-stdin',
    'with-cloud-token npx wrangler deploy',
    # Shell syntax the parser must not trip on
    'for f in *.swift; do echo "$f"; done', 'case "$x" in a) echo a;; *) echo b;; esac',
    'echo $(( 1 + 2 ))', '(( i++ ))', 'arr=(a b c); echo "${arr[@]}"',
    '[[ "$a" == "b" && -n "$c" ]] && echo ok', 'x=$(git rev-parse HEAD) && echo "$x"',
    'diff <(ls a) <(ls b)', 'echo "a)b" ; echo "(c"', 'find . -name "*.py" -exec wc -l {} \\;',
    'git log --format="%H %s" -n 3 | cat', 'print -l **/*(.)',
]


def pre(event):
    proc = subprocess.run([str(LAUNCHER), 'pre'], input=json.dumps(event), capture_output=True,
                          text=True, timeout=30)
    return proc.returncode, proc.stderr


def post(event):
    proc = subprocess.run([str(LAUNCHER), 'post'], input=json.dumps(event), capture_output=True,
                          text=True, timeout=30)
    return proc.returncode, proc.stdout


class PreToolUse(unittest.TestCase):
    def test_blocks_each_way_to_print_a_secret(self):
        for command in BLOCK:
            with self.subTest(command=command):
                code, err = pre({'tool_name': 'Bash', 'tool_input': {'command': command}})
                self.assertEqual(code, 2, command)
                self.assertIn('secret guard', err)
                self.assertIn('bf-secret', err)

    def test_allows_ordinary_and_safe_commands(self):
        for command in ALLOW:
            with self.subTest(command=command):
                code, err = pre({'tool_name': 'Bash', 'tool_input': {'command': command}})
                self.assertEqual(code, 0, '%s\n%s' % (command, err))

    def test_codex_argv_form(self):
        code, _ = pre({'tool_name': 'Bash',
                       'tool_input': {'command': ['bash', '-lc', 'op item get abc']}})
        self.assertEqual(code, 2)
        code, _ = pre({'tool_name': 'Bash', 'tool_input': {'command': ['ls', '-la']}})
        self.assertEqual(code, 0)

    def test_read_grep_and_mcp_tools(self):
        cases = [
            ('Read', {'file_path': '/repo/.env'}, 2),
            ('Read', {'file_path': '/srv/user/.codex/auth.json'}, 2),
            ('Read', {'file_path': '/keys/AuthKey_X.p8'}, 2),
            ('Read', {'file_path': '/repo/.env.example'}, 0),
            ('Read', {'file_path': '/repo/README.md'}, 0),
            ('Grep', {'pattern': 'KEY', 'path': '/repo/.env', 'output_mode': 'content'}, 2),
            ('Grep', {'pattern': 'KEY', 'path': '/repo/.env'}, 0),
            ('Grep', {'pattern': 'x', 'path': '/repo', 'output_mode': 'content'}, 0),
            ('mcp__db__execute_sql', {'query': 'select * from vault.decrypted_secrets'}, 2),
            ('mcp__db__execute_sql', {'query': 'select 1'}, 0),
        ]
        for tool, data, want in cases:
            with self.subTest(tool=tool, data=data):
                self.assertEqual(pre({'tool_name': tool, 'tool_input': data})[0], want)

    def test_bad_input_fails_closed(self):
        proc = subprocess.run([str(LAUNCHER), 'pre'], input='not json', capture_output=True,
                              text=True)
        self.assertEqual(proc.returncode, 2)


class Launcher(unittest.TestCase):
    def test_guard_that_cannot_run_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            shutil.copy2(LAUNCHER, Path(tmp) / 'secret-guard')
            (Path(tmp) / 'secret_guard.py').write_text('this is not python\n')
            proc = subprocess.run([str(Path(tmp) / 'secret-guard'), 'pre'],
                                  input='{"tool_name": "Bash", "tool_input": {"command": "ls"}}',
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 2)
            self.assertIn('BLOCKED', proc.stderr)
            # The output redactor is a backstop: if it cannot run, output passes unchanged.
            proc = subprocess.run([str(Path(tmp) / 'secret-guard'), 'post'], input='{}',
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0)


class PostToolUse(unittest.TestCase):
    def test_redacts_credential_formats_and_keeps_shape(self):
        token = 'sbp_' + '0123456789abcdef' * 2 + '01234567'
        jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZSJ9.' + 'a1B2c3D4e5F6g7H8i9J0'
        pem = '-----BEGIN PRIVATE KEY-----\nMIIEv\n-----END PRIVATE KEY-----'
        url = 'postgres://app:hunter2secret@db.example.com:5432/app'
        response = {'stdout': 'a %s b\n%s\n%s\n%s' % (token, jwt, pem, url), 'stderr': '',
                    'interrupted': False, 'isImage': False}
        code, out = post({'tool_name': 'Bash', 'tool_response': response})
        self.assertEqual(code, 0)
        result = json.loads(out)['hookSpecificOutput']
        cleaned = result['updatedToolOutput']
        self.assertEqual(set(cleaned), set(response))
        for secret in (token, jwt, 'MIIEv', 'hunter2secret'):
            self.assertNotIn(secret, cleaned['stdout'])
        self.assertIn('postgres://app:[REDACTED]@db.example.com', cleaned['stdout'])

    def test_clean_output_is_left_alone(self):
        code, out = post({'tool_name': 'Read', 'tool_response': {
            'type': 'text', 'file': {'content': 'hello world'}}})
        self.assertEqual((code, out), (0, ''))


class BfSecret(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.secret = 'fake-secret-value-123'
        reader = self.tmp / 'reader'
        reader.write_text('#!/bin/sh\n[ "$1" = read ] && [ "$2" = --no-newline ] || exit 9\n'
                          'case "$3" in op://v/i/f) printf %%s %s ;; *) exit 1 ;; esac\n'
                          % self.secret)
        reader.chmod(0o755)
        (self.tmp / 'config/borrowedfire').mkdir(parents=True)
        (self.tmp / 'config/borrowedfire/secret-reader').write_text(str(reader) + '\n')
        self.link = self.tmp / 'bf-secret'
        self.link.symlink_to(LAUNCHER)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.tmp / 'config'))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_wrapper(self, *args):
        return subprocess.run([str(self.link), *args], capture_output=True, text=True,
                              env=self.env, timeout=30)

    def test_env_reaches_child_and_output_is_redacted(self):
        script = self.tmp / 'show.sh'
        script.write_text('#!/bin/sh\necho "got:$T"\necho "err:$T" >&2\n'
                          '[ "$T" = %s ] || exit 4\n' % self.secret)
        script.chmod(0o755)
        proc = self.run_wrapper('--env', 'T=op://v/i/f', '--', str(script))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn(self.secret, proc.stdout + proc.stderr)
        self.assertIn('got:[REDACTED]', proc.stdout)
        self.assertIn('err:[REDACTED]', proc.stderr)

    def test_stdin_and_file_delivery(self):
        script = self.tmp / 'use.sh'
        script.write_text('#!/bin/sh\nread -r line\n[ "$line" = %s ] || exit 5\n'
                          '[ "$(cat "$KEYFILE")" = %s ] || exit 6\n'
                          'ls -l "$KEYFILE" | grep -q "^-rw-------" || exit 7\n'
                          'echo "$KEYFILE" > %s\n' % (self.secret, self.secret,
                                                      self.tmp / 'path'))
        script.chmod(0o755)
        proc = self.run_wrapper('--stdin', 'op://v/i/f', '--file', 'KEYFILE=op://v/i/f', '--',
                                str(script))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(Path((self.tmp / 'path').read_text().strip()).exists())

    def test_exit_status_passes_through(self):
        self.assertEqual(self.run_wrapper('--env', 'T=op://v/i/f', '--', 'false').returncode, 1)

    def test_refuses_printers_shells_and_interpreters(self):
        for child in ('printenv', 'env', 'cat', '/bin/sh', 'bash', 'python3', 'node', 'echo',
                      'tee', 'base64', 'op', 'with-x'):
            with self.subTest(child=child):
                proc = self.run_wrapper('--env', 'T=op://v/i/f', '--', child)
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn('refusing', proc.stderr)
                self.assertNotIn(self.secret, proc.stdout + proc.stderr)

    def test_failed_read_reports_reference_not_value(self):
        proc = self.run_wrapper('--env', 'T=op://v/i/missing', '--', 'true')
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn('could not read op://v/i/missing', proc.stderr)

    def test_usage_errors(self):
        self.assertNotEqual(self.run_wrapper('--', 'true').returncode, 0)
        self.assertNotEqual(self.run_wrapper('--env', '1BAD=op://v/i/f', '--', 'true').returncode,
                            0)


class Registration(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.launcher = '/opt/guard/secret-guard'

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def call(self, *args):
        return subprocess.run([str(LAUNCHER), *args], capture_output=True, text=True)

    def test_claude_settings_keep_other_hooks_and_register_once(self):
        settings = self.tmp / 'settings.json'
        existing = {
            'theme': 'dark',
            'hooks': {'PreToolUse': [{'matcher': 'Bash', 'hooks': [
                {'type': 'command', 'command': '~/.claude/hooks/require-tests-for-pr.sh'}]}],
                'UserPromptSubmit': [{'hooks': [{'type': 'command', 'command': 'x'}]}]},
        }
        settings.write_text(json.dumps(existing, indent=2))
        settings.chmod(0o600)
        for _ in range(2):
            self.assertEqual(self.call('register', 'claude', str(settings),
                                       self.launcher).returncode, 0)
        data = json.loads(settings.read_text())
        self.assertEqual(data['theme'], 'dark')
        commands = [h['command'] for g in data['hooks']['PreToolUse'] for h in g['hooks']]
        self.assertEqual(commands.count('"%s" pre' % self.launcher), 1)
        self.assertIn('~/.claude/hooks/require-tests-for-pr.sh', commands)
        self.assertEqual(len(data['hooks']['PostToolUse']), 1)
        self.assertEqual(data['hooks']['UserPromptSubmit'], existing['hooks']['UserPromptSubmit'])
        self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
        self.assertEqual(self.call('registered', 'claude', str(settings),
                                   self.launcher).returncode, 0)
        before = settings.read_bytes()
        self.call('register', 'claude', str(settings), self.launcher)
        self.assertEqual(settings.read_bytes(), before)

        self.assertEqual(self.call('unregister', 'claude', str(settings),
                                   self.launcher).returncode, 0)
        data = json.loads(settings.read_text())
        self.assertNotIn('PostToolUse', data['hooks'])
        self.assertEqual(data['hooks']['PreToolUse'], existing['hooks']['PreToolUse'])
        self.assertNotEqual(self.call('registered', 'claude', str(settings),
                                      self.launcher).returncode, 0)

    def test_codex_hooks_file_created_and_duplicates_collapsed(self):
        hooks = self.tmp / 'hooks.json'
        self.call('register', 'codex', str(hooks), self.launcher)
        data = json.loads(hooks.read_text())
        data['hooks']['PreToolUse'].append(data['hooks']['PreToolUse'][0])
        hooks.write_text(json.dumps(data))
        self.assertNotEqual(self.call('registered', 'codex', str(hooks),
                                      self.launcher).returncode, 0)
        self.call('register', 'codex', str(hooks), self.launcher)
        self.assertEqual(self.call('registered', 'codex', str(hooks),
                                   self.launcher).returncode, 0)
        self.assertNotIn('PostToolUse', json.loads(hooks.read_text())['hooks'])

    def test_malformed_settings_are_not_rewritten(self):
        settings = self.tmp / 'settings.json'
        settings.write_text('{"hooks": [1]}')
        self.assertNotEqual(self.call('register', 'claude', str(settings),
                                      self.launcher).returncode, 0)
        self.assertEqual(settings.read_text(), '{"hooks": [1]}')


if __name__ == '__main__':
    unittest.main(verbosity=1)
