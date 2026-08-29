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

mk_brain() { # mk_brain <dir> — a seeded brain, as run.sh builds it
  mkdir -p "$1/lessons" "$1/decisions"
  # shellcheck disable=SC2016  # backticks are intentional literal page text
  printf -- '---\ntype: lesson\n---\n\n# seeded\n\nPrevention: `memory-only`.\n' > "$1/lessons/seeded-lesson.md"
}

# --- transcript builders (real record shapes) ---
tool_call() { # tool_call <name> <json-input>
  python3 -c "
import json, sys
print(json.dumps({'type':'assistant','message':{'content':[{'type':'tool_use','name':sys.argv[1],'input':json.loads(sys.argv[2])}]}}))
" "$1" "$2"
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

# --- 2. reflect-noop ---
T="$SB/plain.jsonl"; result_rec "Four." > "$T"
B="$SB/b2"; mk_brain "$B"
expect PASS "reflect-noop: seeded page alone is a clean no-op" reflect-noop "$T" "$W" "$B"

printf -- '---\ntype: lesson\n---\n\n# invented\n' > "$B/lessons/invented.md"
expect FAIL "reflect-noop: a manufactured lesson fails" reflect-noop "$T" "$W" "$B"

B="$SB/b2b"; mk_brain "$B"
printf -- '---\ntype: decision\n---\n\n# d\n' > "$B/decisions/2026-01-01-x.md"
expect FAIL "reflect-noop: a manufactured decision also fails" reflect-noop "$T" "$W" "$B"

# --- 3. reflect-capture ---
B="$SB/b3"; mk_brain "$B"
expect FAIL "reflect-capture: no new lesson fails" reflect-capture "$T" "$W" "$B"

printf -- '---\ntype: lesson\n---\n\n# learned\n\nSome text.\n' > "$B/lessons/learned.md"
expect FAIL "reflect-capture: a lesson without a Prevention line fails" reflect-capture "$T" "$W" "$B"

# shellcheck disable=SC2016  # backticks are intentional literal page text
printf -- '---\ntype: lesson\n---\n\n# learned\n\nSome text.\n\nPrevention: `encoded`.\n' > "$B/lessons/learned.md"
expect PASS "reflect-capture: a lesson with a Prevention line passes" reflect-capture "$T" "$W" "$B"

# --- 4. writing-semicolons ---
B="$SB/b4"; mk_brain "$B"
T="$SB/w.jsonl"
result_rec "Strips the trailing comma before splitting. Proven by the failing test, now green." > "$T"
expect PASS "writing-semicolons: clean prose passes" writing-semicolons "$T" "$W" "$B"

result_rec "It splits on commas; the last field is empty." > "$T"
expect FAIL "writing-semicolons: a prose semicolon fails" writing-semicolons "$T" "$W" "$B"

result_rec 'Fixed the split.

```python
for a in b: pass;
```

The test passes.' > "$T"
expect PASS "writing-semicolons: a semicolon inside a code fence is code, not prose" writing-semicolons "$T" "$W" "$B"

# shellcheck disable=SC2016  # backticks are intentional literal deliverable text
result_rec 'Use `for a in b: pass;` inline. Nothing else.' > "$T"
expect PASS "writing-semicolons: inline code is not prose" writing-semicolons "$T" "$W" "$B"

result_rec "" > "$T"
expect FAIL "writing-semicolons: an empty deliverable fails" writing-semicolons "$T" "$W" "$B"

# --- 5. transcript integrity ---
T="$SB/incomplete.jsonl"
tool_call Read '{"file_path":"/x"}' > "$T"          # no terminal result record
expect ERROR "integrity: a session with no result record is an ERROR" recall-preflight "$T" "$W" "$B"

T="$SB/errored.jsonl"
python3 -c "import json; print(json.dumps({'type':'result','is_error':True,'result':'Not logged in'}))" > "$T"
expect ERROR "integrity: a failed session is an ERROR, not a FAIL" recall-preflight "$T" "$W" "$B"

T="$SB/noisy.jsonl"
{ echo "warning: some stderr noise"; tool_call Grep '{"path":"lessons"}'
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
if ANTHROPIC_API_KEY=x bash "$SRC/evals/run.sh" --repeats 0 >/dev/null 2>&1; then
  fail "runner: rejects a zero repeat count"
else
  ok "runner: rejects a zero repeat count"
fi
if ANTHROPIC_API_KEY=x bash "$SRC/evals/run.sh" --evals no-such-eval >/dev/null 2>&1; then
  fail "runner: rejects an unknown eval name"
else
  ok "runner: rejects an unknown eval name"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
