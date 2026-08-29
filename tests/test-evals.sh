#!/usr/bin/env bash
# Prove the eval scorer against transcripts in the real stream-json shape.
#
# The live cells need an API key and cost real money, so the scorer is what gets tested here:
# fixtures are hand-built to the exact record shape `claude -p --output-format stream-json`
# emits (assistant.message.content[].tool_use with name+input, a terminal result record), and
# each eval is exercised on a passing case, a failing case, and a malformed transcript.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

score() { python3 "$SRC/evals/score.py" "$1" "$2" "$3" "$4" 2>&1; }

expect() { # expect <want-verdict> <desc> <eval> <transcript> <workspace> <brain>
  local want="$1" desc="$2"
  shift 2
  local got
  got="$(score "$@" | awk '{print $2}')"
  if [ "$got" = "$want" ]; then ok "$desc"; else fail "$desc (got '$got', want '$want')"; fi
}

mk_brain() { # mk_brain <dir> — a seeded brain committed to git, as run.sh builds it
  mkdir -p "$1/lessons" "$1/decisions" "$1/inbox"
  # shellcheck disable=SC2016  # backticks are intentional literal page text
  printf -- '---\ntype: lesson\n---\n\n# seeded\n\nPrevention: `memory-only`.\n' > "$1/lessons/seeded-lesson.md"
  printf 'placeholder\n' > "$1/inbox/.keep"
  git -C "$1" init -q .
  git -C "$1" add -A
  git -C "$1" -c user.email=e@e -c user.name=e commit -qm seed
}

# --- transcript builders (real record shapes) ---
tool_call() { # tool_call <name> <json-input>
  python3 -c "
import json, sys
print(json.dumps({'type':'assistant','message':{'content':[{'type':'tool_use','name':sys.argv[1],'input':json.loads(sys.argv[2])}]}}))
" "$1" "$2"
}
init_rec() { # init_rec <space-separated skill names>
  python3 -c "
import json, sys
print(json.dumps({'type':'system','subtype':'init','skills':sys.argv[1].split() if sys.argv[1] else []}))
" "$1"
}
result_rec() { # result_rec <text>
  python3 -c "
import json, sys
print(json.dumps({'type':'result','subtype':'success','is_error':False,'result':sys.argv[1]}))
" "$1"
}

W="$SB/work"; mkdir -p "$W"

# --- 1. recall-preflight ---
B="$SB/b1"; mk_brain "$B"
T="$SB/recall-pass.jsonl"
{ tool_call Grep '{"pattern":"widget","path":"/x/brain/lessons"}'
  tool_call Read '{"file_path":"/x/brain/lessons/seeded-lesson.md"}'
  tool_call Edit '{"file_path":"/x/work/widget.py"}'
  result_rec "fixed"; } > "$T"
expect PASS "recall-preflight: lessons read before the write" recall-preflight "$T" "$W" "$B"

T="$SB/recall-late.jsonl"
{ tool_call Read '{"file_path":"/x/work/widget.py"}'
  tool_call Edit '{"file_path":"/x/work/widget.py"}'
  tool_call Grep '{"pattern":"widget","path":"/x/brain/lessons"}'
  result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: reading lessons after the write does not count" recall-preflight "$T" "$W" "$B"

T="$SB/recall-none.jsonl"
{ tool_call Edit '{"file_path":"/x/work/widget.py"}'; result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: no lessons read at all fails" recall-preflight "$T" "$W" "$B"

T="$SB/recall-nowrite.jsonl"
{ tool_call Grep '{"pattern":"widget","path":"/x/brain/lessons"}'; result_rec "read only"; } > "$T"
expect PASS "recall-preflight: a session that never writes still counts the read" recall-preflight "$T" "$W" "$B"

# A shell mutation is a write. Without this the scorer calls a later lessons/ read "first".
T="$SB/recall-sed.jsonl"
{ tool_call Bash '{"command":"sed -i.bak s/x/y/ widget.py"}'
  tool_call Grep '{"pattern":"widget","path":"/x/brain/lessons"}'
  result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: a sed -i edit counts as the first write" recall-preflight "$T" "$W" "$B"

T="$SB/recall-redirect.jsonl"
{ tool_call Bash '{"command":"printf %s\\n code > widget.py"}'
  tool_call Read '{"file_path":"/x/brain/lessons/seeded-lesson.md"}'
  result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: a shell redirect counts as the first write" recall-preflight "$T" "$W" "$B"

T="$SB/recall-readonly-bash.jsonl"
{ tool_call Bash '{"command":"python3 -m pytest -q"}'
  tool_call Grep '{"pattern":"widget","path":"/x/brain/lessons"}'
  tool_call Edit '{"file_path":"/x/work/widget.py"}'
  result_rec "fixed"; } > "$T"
expect PASS "recall-preflight: running the tests is not a write" recall-preflight "$T" "$W" "$B"

# Saying the word is not reading the page. These three touch no brain file.
T="$SB/recall-todo.jsonl"
{ tool_call TodoWrite '{"todos":[{"content":"Check the brain lessons first"}]}'
  tool_call Edit '{"file_path":"/x/work/widget.py"}'; result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: a todo that plans to read lessons is not a read" recall-preflight "$T" "$W" "$B"

T="$SB/recall-desc.jsonl"
{ tool_call Bash '{"command":"pytest -q","description":"Run tests before consulting lessons"}'
  tool_call Edit '{"file_path":"/x/work/widget.py"}'; result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: the word in a description is not a read" recall-preflight "$T" "$W" "$B"

T="$SB/recall-workspace.jsonl"
{ tool_call Grep '{"pattern":"lessons","path":"/x/work"}'
  tool_call Edit '{"file_path":"/x/work/widget.py"}'; result_rec "fixed"; } > "$T"
expect FAIL "recall-preflight: grepping the workspace for the word is not a brain read" recall-preflight "$T" "$W" "$B"

# --- 2. reflect-noop ---
T="$SB/plain.jsonl"; result_rec "Four." > "$T"
B="$SB/b2"; mk_brain "$B"
expect PASS "reflect-noop: an untouched seeded brain is a clean no-op" reflect-noop "$T" "$W" "$B"

printf -- '---\ntype: lesson\n---\n\n# invented\n' > "$B/lessons/invented.md"
expect FAIL "reflect-noop: a manufactured lesson fails" reflect-noop "$T" "$W" "$B"

B="$SB/b2b"; mk_brain "$B"
printf -- '---\ntype: decision\n---\n\n# d\n' > "$B/decisions/2026-01-01-x.md"
expect FAIL "reflect-noop: a manufactured decision also fails" reflect-noop "$T" "$W" "$B"

# The whole tree counts, not two chosen directories.
B="$SB/b2c"; mk_brain "$B"
printf -- 'raw capture\n' > "$B/inbox/2026-01-01-thing-agent.md"
expect FAIL "reflect-noop: a capture into inbox/ also fails" reflect-noop "$T" "$W" "$B"

B="$SB/b2d"; mk_brain "$B"
printf -- '\n- 2026-01-01: edited in place [x@y]\n' >> "$B/lessons/seeded-lesson.md"
expect FAIL "reflect-noop: editing an existing page also fails" reflect-noop "$T" "$W" "$B"

expect FAIL "reflect-noop: a brain that is not a git repo cannot be scored" reflect-noop "$T" "$W" "$SB/not-a-repo"

# remember COMMITS every capture. Measuring the working tree would report a clean brain for a
# session that followed the doctrine exactly, so the delta is taken against the seed commit.
commit_in() { git -C "$1" add -A && git -C "$1" -c user.email=e@e -c user.name=e commit -qm "$2"; }
B="$SB/b2e"; mk_brain "$B"
printf -- '---\ntype: lesson\n---\n\n# invented\n' > "$B/lessons/invented.md"
commit_in "$B" "brain: capture lessons/invented.md [x@y]"
expect FAIL "reflect-noop: a COMMITTED manufactured lesson still fails" reflect-noop "$T" "$W" "$B"

# --- 3. reflect-capture ---
B="$SB/b3"; mk_brain "$B"
expect FAIL "reflect-capture: no new lesson fails" reflect-capture "$T" "$W" "$B"

printf -- 'raw\n' > "$B/inbox/2026-01-01-x-agent.md"
expect FAIL "reflect-capture: a capture that lands outside lessons/ fails" reflect-capture "$T" "$W" "$B"

printf -- '---\ntype: lesson\n---\n\n# learned\n\nSome text.\n' > "$B/lessons/learned.md"
expect FAIL "reflect-capture: a lesson without a Prevention line fails" reflect-capture "$T" "$W" "$B"

# shellcheck disable=SC2016  # backticks are intentional literal page text
printf -- '---\ntype: lesson\n---\n\n# learned\n\nSome text.\n\nPrevention: `encoded`.\n' > "$B/lessons/learned.md"
expect PASS "reflect-capture: a lesson with a Prevention line passes" reflect-capture "$T" "$W" "$B"

B="$SB/b3b"; mk_brain "$B"
# shellcheck disable=SC2016  # backticks are intentional literal page text
printf -- '---\ntype: lesson\n---\n\n# learned\n\nText.\n\nPrevention: `encoded`.\n' > "$B/lessons/learned.md"
commit_in "$B" "brain: capture lessons/learned.md [x@y]"
expect PASS "reflect-capture: a COMMITTED capture is still seen" reflect-capture "$T" "$W" "$B"

# --- 4. writing-punctuation ---
B="$SB/b4"; mk_brain "$B"
T="$SB/w.jsonl"
result_rec "Strips the trailing comma before splitting. Proven by the failing test, now green." > "$T"
expect PASS "writing-punctuation: clean prose passes" writing-punctuation "$T" "$W" "$B"

result_rec "It splits on commas; the last field is empty." > "$T"
expect FAIL "writing-punctuation: a prose semicolon fails" writing-punctuation "$T" "$W" "$B"

result_rec 'Fixed the split.

```python
for a in b: pass;
```

The test passes.' > "$T"
expect PASS "writing-punctuation: a semicolon inside a code fence is code, not prose" writing-punctuation "$T" "$W" "$B"

# shellcheck disable=SC2016  # backticks are intentional literal deliverable text
result_rec 'Use `for a in b: pass;` inline. Nothing else.' > "$T"
expect PASS "writing-punctuation: inline code is not prose" writing-punctuation "$T" "$W" "$B"

result_rec "" > "$T"
expect FAIL "writing-punctuation: an empty deliverable fails" writing-punctuation "$T" "$W" "$B"

result_rec "The parser kept an empty field — the feed ends every record with a comma." > "$T"
expect FAIL "writing-punctuation: an em dash fails too" writing-punctuation "$T" "$W" "$B"

result_rec 'Fixed it.

```python
x = 1;
' > "$T"
expect ERROR "writing-punctuation: an unbalanced fence is unscoreable, not a pass" writing-punctuation "$T" "$W" "$B"

# --- 4b. arm verification: the treatment must actually be present ---
arm_check() { python3 "$SRC/evals/score.py" --verify-arm "$1" "$2" >/dev/null 2>&1; }

T="$SB/arm-doctrine.jsonl"
{ init_rec "recall remember digest reflect land ship"; result_rec "ok"; } > "$T"
if arm_check doctrine "$T"; then ok "arm: a doctrine cell seeing the skills verifies"; else fail "arm: a doctrine cell seeing the skills verifies"; fi
if arm_check bare "$T"; then fail "arm: those same skills fail the bare check"; else ok "arm: those same skills fail the bare check"; fi

T="$SB/arm-bare.jsonl"
{ init_rec "commit pr-review"; result_rec "ok"; } > "$T"
if arm_check bare "$T"; then ok "arm: a bare cell with unrelated skills verifies"; else fail "arm: a bare cell with unrelated skills verifies"; fi
# This is the case that would have caught --setting-sources stripping the doctrine.
if arm_check doctrine "$T"; then fail "arm: a doctrine cell that loaded no skills fails"; else ok "arm: a doctrine cell that loaded no skills fails"; fi

T="$SB/arm-partial.jsonl"
{ init_rec "recall remember"; result_rec "ok"; } > "$T"
if arm_check doctrine "$T"; then fail "arm: a partially installed doctrine cell fails"; else ok "arm: a partially installed doctrine cell fails"; fi

T="$SB/arm-noinit.jsonl"; result_rec "ok" > "$T"
if arm_check doctrine "$T"; then fail "arm: a transcript with no init record fails"; else ok "arm: a transcript with no init record fails"; fi
if arm_check doctrine "$SB/nope.jsonl"; then fail "arm: a missing transcript fails"; else ok "arm: a missing transcript fails"; fi

# --- 5. transcript integrity ---
T="$SB/incomplete.jsonl"
tool_call Read '{"file_path":"/x"}' > "$T"          # no terminal result record
expect ERROR "integrity: a session with no result record is an ERROR" recall-preflight "$T" "$W" "$B"

T="$SB/errored.jsonl"
python3 -c "import json; print(json.dumps({'type':'result','is_error':True,'result':'Not logged in'}))" > "$T"
expect ERROR "integrity: a failed session is an ERROR, not a FAIL" recall-preflight "$T" "$W" "$B"

T="$SB/noisy.jsonl"
{ echo "warning: some stderr noise"; tool_call Grep '{"path":"/x/brain/lessons"}'
  echo "not json at all"; tool_call Edit '{"file_path":"/x"}'; result_rec "done"; } > "$T"
expect PASS "integrity: non-JSON noise lines are skipped, not fatal" recall-preflight "$T" "$W" "$B"

expect ERROR "integrity: an unknown eval name is an ERROR" no-such-eval "$T" "$W" "$B"

# --- 6. the runner refuses to run un-isolated ---
if OUT="$(env -u ANTHROPIC_API_KEY bash "$SRC/evals/run.sh" 2>&1)"; then
  fail "runner: refuses to run without an API key"
else
  ok "runner: refuses to run without an API key"
fi
if grep -q 'ANTHROPIC_API_KEY is not set' <<<"$OUT"; then
  ok "runner: names the missing key"
else
  fail "runner: names the missing key"
fi
if grep -q 'no un-isolated mode' <<<"$OUT"; then
  ok "runner: states why there is no fallback"
else
  fail "runner: states why there is no fallback"
fi
# Assert the exact refusal text, not just a nonzero exit. On a box without the claude CLI these
# used to pass at the PATH guard, so deleting the validation entirely left the suite green.
refusal() { # refusal <expected-text> <desc> <flag...>
  local want="$1" desc="$2"
  shift 2
  local out
  out="$(ANTHROPIC_API_KEY=x bash "$SRC/evals/run.sh" "$@" 2>&1)"
  if grep -qF -- "$want" <<<"$out"; then ok "$desc"; else fail "$desc (said: $(head -1 <<<"$out"))"; fi
}
refusal "--repeats must be at least 1" "runner: rejects a zero repeat count" --repeats 0
refusal "--repeats needs a number" "runner: rejects a non-numeric repeat count" --repeats two
refusal "unknown eval 'no-such-eval'" "runner: rejects an unknown eval name" --evals no-such-eval
refusal "unknown arm 'banana'" "runner: rejects an unknown arm" --arms doctrine,banana
refusal "unknown arm 'doctrin'" "runner: a misspelled arm is refused, not silently run" --arms doctrin,bare

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
