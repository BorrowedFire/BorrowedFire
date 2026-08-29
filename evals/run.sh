#!/usr/bin/env bash
# Measure whether the doctrine changes agent behavior, not whether the installer works.
#
# Each cell is one headless Claude Code session in a throwaway sandbox: its own HOME, its own
# git workspace, its own brain. The `doctrine` arm installs the Borrowed Fire skills into that
# HOME; the `bare` arm installs nothing. A doctrine rule that fires shows up as a gap between
# the arms. A rule that passes in both arms is not being carried by the doctrine.
#
# Usage: evals/run.sh [--evals a,b] [--arms doctrine,bare] [--repeats N] [--model M] [--keep]
#
# Requires ANTHROPIC_API_KEY. A sandbox HOME cannot read the interactive login (OAuth lives in
# the keychain), and running against the operator's real HOME would load their skills into both
# arms — the contamination that makes a benchmark lie. This script refuses that run rather than
# reporting a number it cannot stand behind.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVALS="recall-preflight,reflect-noop,reflect-capture,writing-punctuation"
ARMS="doctrine,bare"
REPEATS=2
MODEL=""
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --evals) shift; EVALS="${1:-}" ;;
    --arms) shift; ARMS="${1:-}" ;;
    --repeats) shift; REPEATS="${1:-}" ;;
    --model) shift; MODEL="${1:-}" ;;
    --keep) KEEP=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# Argument validation runs before the environment guards below. A CI box without the CLI must
# still fail an invalid flag, or these checks can only ever be tested where the CLI exists.
case "$REPEATS" in ''|*[!0-9]*) echo "evals: --repeats needs a number" >&2; exit 2 ;; esac
[ "$REPEATS" -ge 1 ] || { echo "evals: --repeats must be at least 1" >&2; exit 2; }
IFS=',' read -r -a EVAL_LIST <<< "$EVALS"
IFS=',' read -r -a ARM_LIST <<< "$ARMS"
[ "${#EVAL_LIST[@]}" -gt 0 ] || { echo "evals: --evals is empty" >&2; exit 2; }
[ "${#ARM_LIST[@]}" -gt 0 ] || { echo "evals: --arms is empty" >&2; exit 2; }
for arm in "${ARM_LIST[@]}"; do
  case "$arm" in
    doctrine|bare) ;;
    # An unrecognized arm used to fall through to the bare configuration: it burned a paid cell
    # and then vanished from the report, so a typo looked like a total doctrine failure.
    *) echo "evals: unknown arm '$arm' (expected doctrine or bare)" >&2; exit 2 ;;
  esac
done
for eval_name in "${EVAL_LIST[@]}"; do
  case "$eval_name" in
    recall-preflight|reflect-noop|reflect-capture|writing-punctuation) ;;
    *) echo "evals: unknown eval '$eval_name'" >&2; exit 2 ;;
  esac
done

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  cat >&2 <<'MSG'
evals: ANTHROPIC_API_KEY is not set.

Every cell runs in a sandbox HOME so the two arms differ only by the installed skills. A
sandbox HOME cannot use the interactive login, and reusing the real HOME would load the
operator's own skills into the bare arm, so both arms would measure the same thing.

Export a key and re-run. There is no un-isolated mode on purpose.
MSG
  exit 1
fi
command -v claude >/dev/null 2>&1 || { echo "evals: the claude CLI is not on PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "evals: python3 is required for scoring" >&2; exit 1; }

RUN_DIR="$(mktemp -d)"
RESULTS="$RUN_DIR/results.tsv"
: > "$RESULTS"
echo "evals: run directory $RUN_DIR"

# --- fixtures -------------------------------------------------------------------------------
# One seeded lesson the recall preflight is supposed to find, and a repo whose bug it names.
seed_brain() { # seed_brain <brain-dir>
  local b="$1"
  cp -R "$ROOT/prometheus-template" "$b"
  cat > "$b/lessons/seeded-lesson.md" <<'PAGE'
---
type: lesson
created: 2026-01-02
updated: 2026-01-02
tags: [widget, parsing]
source: agent-run
status: active
---

# parse_widget rejects a trailing comma, and callers pass one

The widget feed emits a trailing comma on every record. `parse_widget` in `widget.py` splits on
"," and then fails on the empty final field. Strip the trailing comma before splitting. Two
earlier fixes patched the callers instead and both regressed.

Prevention: `memory-only`.
PAGE
  git -C "$b" init -q .
  git -C "$b" add -A
  git -C "$b" -c user.email=e@e -c user.name=e commit -qm "seed"
}

seed_workspace() { # seed_workspace <workspace-dir>
  local w="$1"
  mkdir -p "$w"
  cat > "$w/widget.py" <<'PAGE'
def parse_widget(line):
    """Return the fields of one widget record."""
    return [field.strip() for field in line.split(",")]


def widget_count(line):
    return len(parse_widget(line))
PAGE
  cat > "$w/test_widget.py" <<'PAGE'
from widget import widget_count


def test_trailing_comma():
    assert widget_count("a,b,c,") == 3
PAGE
  git -C "$w" init -q .
  git -C "$w" add -A
  git -C "$w" -c user.email=e@e -c user.name=e commit -qm "seed"
}

# A prompt states the task the way a user would, and never names the rule under test. Asking
# for the behavior measures instruction following, not whether the doctrine fires on its own,
# and a prompt that forbids its own failure mode cannot fail in either arm.
prompt_for() { # prompt_for <eval>
  case "$1" in
    recall-preflight)
      echo "test_widget.py fails. Fix the bug in widget.py so it passes." ;;
    reflect-noop)
      echo "What does widget_count(\"a,b\") return? Answer with the number." ;;
    reflect-capture)
      echo "test_widget.py fails: parse_widget keeps an empty field from the feed's trailing comma, and the two previous fixes patched the callers instead. Fix widget.py so the test passes." ;;
    writing-punctuation)
      echo "Write the body of a pull request description for a change that strips a trailing comma before splitting a widget record. Cover the problem, the fix, and how it was proven. Output the body only." ;;
    *) return 1 ;;
  esac
}

# --- run ------------------------------------------------------------------------------------
CELLS=0
FAILED_CELLS=0

for eval_name in "${EVAL_LIST[@]}"; do
  [ -n "$eval_name" ] || continue
  for arm in "${ARM_LIST[@]}"; do
    [ -n "$arm" ] || continue
    rep=1
    while [ "$rep" -le "$REPEATS" ]; do
      cell="$RUN_DIR/$eval_name.$arm.$rep"
      # Both arms get the same HOME shape. install.sh only sees a harness when its root dir
      # exists, so .claude is created either way: without it the doctrine arm would install
      # nothing and both arms would measure the same thing.
      mkdir -p "$cell/home/.claude" "$cell/home/.config"
      seed_brain "$cell/brain"
      seed_workspace "$cell/work"

      if [ "$arm" = "doctrine" ]; then
        # CODEX_HOME is redirected, never inherited: an exported one points at the operator's
        # real Codex root, and install.sh would rewrite it.
        HOME="$cell/home" XDG_CONFIG_HOME="$cell/home/.config" CODEX_HOME="$cell/home/.codex" \
          "$ROOT/install.sh" --copy --brain "$cell/brain" >"$cell/install.log" 2>&1 || {
            echo "evals: install failed for $eval_name/$arm/$rep, see $cell/install.log" >&2
            FAILED_CELLS=$((FAILED_CELLS + 1)); rep=$((rep + 1)); continue
          }
        [ -d "$cell/home/.claude/skills" ] || {
          echo "evals: install wrote no skills for $eval_name/$arm/$rep; the arms would be identical" >&2
          FAILED_CELLS=$((FAILED_CELLS + 1)); rep=$((rep + 1)); continue
        }
      fi   # bare arm: a HOME with no skills and no doctrine

      # Do NOT restrict --setting-sources. install.sh writes the skills and the doctrine block
      # into the *user* source of this cell's HOME, so excluding `user` would strip the very
      # treatment being measured and make both arms identical. Isolation comes from the sandbox
      # HOME, never from dropping the source the doctrine lives in.
      set -- -p "$(prompt_for "$eval_name")"
      set -- "$@" --output-format stream-json --verbose
      set -- "$@" --permission-mode acceptEdits
      # Granted to BOTH arms on purpose: an asymmetric grant would let the doctrine arm reach a
      # brain the bare arm physically cannot, so every gap would measure the grant, not the rule.
      set -- "$@" --add-dir "$cell/brain"
      [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"

      ( cd "$cell/work" && HOME="$cell/home" XDG_CONFIG_HOME="$cell/home/.config" \
          CODEX_HOME="$cell/home/.codex" PROMETHEUS_DIR="$cell/brain" claude "$@" ) \
        > "$cell/transcript.jsonl" 2> "$cell/stderr.log"

      # Live-fire check before scoring: the session's own init record must show the doctrine
      # arm seeing the Borrowed Fire skills and the bare arm not seeing them. Without this the
      # harness cannot tell "the rule did nothing" from "the rule was never loaded", which is
      # the difference between a finding and a lie.
      if ! arm_note="$(python3 "$ROOT/evals/score.py" --verify-arm "$arm" "$cell/transcript.jsonl" 2>&1)"; then
        printf '  %-20s %-9s rep %s  ARM-CHECK FAILED %s\n' "$eval_name" "$arm" "$rep" "$arm_note"
        printf '%s\t%s\t%s\t%s\n' "$eval_name" "$arm" "$rep" "$eval_name ERROR arm check: $arm_note" >> "$RESULTS"
        CELLS=$((CELLS + 1)); FAILED_CELLS=$((FAILED_CELLS + 1)); rep=$((rep + 1)); continue
      fi

      verdict="$(python3 "$ROOT/evals/score.py" "$eval_name" \
        "$cell/transcript.jsonl" "$cell/work" "$cell/brain")"
      status=$?
      # An empty verdict means the scorer died before printing. Anything other than a clean
      # pass or fail is an error, never a silent doctrine failure.
      if [ -z "$verdict" ] || { [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; }; then
        verdict="$eval_name ERROR scorer exited $status"
        FAILED_CELLS=$((FAILED_CELLS + 1))
      fi
      printf '%s\t%s\t%s\t%s\n' "$eval_name" "$arm" "$rep" "$verdict" >> "$RESULTS"
      printf '  %-20s %-9s rep %s  %s\n' "$eval_name" "$arm" "$rep" "$verdict"
      CELLS=$((CELLS + 1))
      rep=$((rep + 1))
    done
  done
done

# --- report ---------------------------------------------------------------------------------
echo
echo "evals: $CELLS cell(s)"
REPORT_OK=1
python3 - "$RESULTS" <<'PY' || REPORT_OK=0
import collections, sys, pathlib
tally = collections.defaultdict(lambda: collections.Counter())
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if not line.strip():
        continue
    # A verdict can contain tabs or be empty when a cell died. Split off the three leading
    # fields and keep the rest whole, so one damaged row cannot destroy the whole report.
    parts = line.split("\t", 3)
    if len(parts) < 4:
        continue
    name, arm, _rep, verdict = parts
    words = verdict.split()
    tally[name][arm, words[1] if len(words) > 1 else "ERROR"] += 1
width = max((len(n) for n in tally), default=10)
print(f"{'eval'.ljust(width)}  doctrine      bare")
for name in sorted(tally):
    counts = tally[name]
    def cell(arm):
        p, f, e = counts[arm, "PASS"], counts[arm, "FAIL"], counts[arm, "ERROR"]
        return f"{p}P/{f}F" + (f"/{e}E" if e else "")
    print(f"{name.ljust(width)}  {cell('doctrine').ljust(12)}  {cell('bare')}")
print()
print("A doctrine rule is firing when doctrine passes and bare does not. Equal columns mean the")
print("rule is not what produced the behavior — the model would have done it either way.")
PY

# Keep the evidence whenever anything went wrong. A run that deletes its own transcripts after
# a failure leaves nothing to diagnose with.
if [ "$KEEP" -eq 1 ] || [ "$FAILED_CELLS" -ne 0 ] || [ "$REPORT_OK" -eq 0 ]; then
  echo "evals: transcripts kept in $RUN_DIR"
else
  rm -rf "$RUN_DIR"
  echo "evals: run directory removed (pass --keep to inspect transcripts)"
fi
[ "$REPORT_OK" -eq 1 ] || { echo "evals: the summary could not be built from $RESULTS" >&2; exit 1; }
[ "$FAILED_CELLS" -eq 0 ] || { echo "evals: $FAILED_CELLS cell(s) did not produce a usable result" >&2; exit 1; }
