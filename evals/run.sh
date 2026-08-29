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
EVALS="recall-preflight,reflect-noop,reflect-capture,writing-semicolons"
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
case "$REPEATS" in ''|*[!0-9]*) echo "evals: --repeats needs a number" >&2; exit 2 ;; esac
[ "$REPEATS" -ge 1 ] || { echo "evals: --repeats must be at least 1" >&2; exit 2; }

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

prompt_for() { # prompt_for <eval>
  case "$1" in
    recall-preflight)
      echo "test_widget.py fails. Fix the bug in widget.py so it passes." ;;
    reflect-noop)
      echo "What is 2 + 2? Answer in one word. Change no files." ;;
    reflect-capture)
      echo "test_widget.py fails because parse_widget keeps an empty field from the feed's trailing comma. Fix widget.py, then record what a future session should know so this class of bug is not re-patched at the callers." ;;
    writing-semicolons)
      echo "Write the body of a pull request description for a change that strips a trailing comma before splitting a widget record. Cover the problem, the fix, and how it was proven. Output the body only." ;;
    *) return 1 ;;
  esac
}

# --- run ------------------------------------------------------------------------------------
IFS=',' read -r -a EVAL_LIST <<< "$EVALS"
IFS=',' read -r -a ARM_LIST <<< "$ARMS"
CELLS=0
FAILED_CELLS=0

for eval_name in "${EVAL_LIST[@]}"; do
  [ -n "$eval_name" ] || continue
  if ! prompt_for "$eval_name" >/dev/null; then
    echo "evals: unknown eval '$eval_name'" >&2
    exit 2
  fi
  for arm in "${ARM_LIST[@]}"; do
    [ -n "$arm" ] || continue
    rep=1
    while [ "$rep" -le "$REPEATS" ]; do
      cell="$RUN_DIR/$eval_name.$arm.$rep"
      mkdir -p "$cell/home"
      seed_brain "$cell/brain"
      seed_workspace "$cell/work"

      if [ "$arm" = "doctrine" ]; then
        HOME="$cell/home" XDG_CONFIG_HOME="$cell/home/.config" \
          "$ROOT/install.sh" --copy --brain "$cell/brain" >"$cell/install.log" 2>&1 || {
            echo "evals: install failed for $eval_name/$arm/$rep, see $cell/install.log" >&2
            FAILED_CELLS=$((FAILED_CELLS + 1)); rep=$((rep + 1)); continue
          }
      else
        mkdir -p "$cell/home/.claude"   # a HOME with no skills and no doctrine
      fi

      set -- -p "$(prompt_for "$eval_name")"
      set -- "$@" --output-format stream-json --verbose
      set -- "$@" --setting-sources project,local --permission-mode acceptEdits
      set -- "$@" --add-dir "$cell/brain"
      [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"

      ( cd "$cell/work" && HOME="$cell/home" XDG_CONFIG_HOME="$cell/home/.config" \
          PROMETHEUS_DIR="$cell/brain" claude "$@" ) \
        > "$cell/transcript.jsonl" 2> "$cell/stderr.log"

      verdict="$(python3 "$ROOT/evals/score.py" "$eval_name" \
        "$cell/transcript.jsonl" "$cell/work" "$cell/brain")"
      status=$?
      printf '%s\t%s\t%s\t%s\n' "$eval_name" "$arm" "$rep" "$verdict" >> "$RESULTS"
      printf '  %-20s %-9s rep %s  %s\n' "$eval_name" "$arm" "$rep" "$verdict"
      CELLS=$((CELLS + 1))
      [ "$status" -eq 2 ] && FAILED_CELLS=$((FAILED_CELLS + 1))
      rep=$((rep + 1))
    done
  done
done

# --- report ---------------------------------------------------------------------------------
echo
echo "evals: $CELLS cell(s)"
python3 - "$RESULTS" <<'PY'
import collections, sys, pathlib
rows = [l.split("\t") for l in pathlib.Path(sys.argv[1]).read_text().splitlines() if l.strip()]
tally = collections.defaultdict(lambda: collections.Counter())
for name, arm, _rep, verdict in rows:
    tally[name][arm, verdict.split()[1]] += 1
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

if [ "$KEEP" -eq 1 ]; then
  echo "evals: transcripts kept in $RUN_DIR"
else
  rm -rf "$RUN_DIR"
  echo "evals: run directory removed (pass --keep to inspect transcripts)"
fi
[ "$FAILED_CELLS" -eq 0 ] || { echo "evals: $FAILED_CELLS cell(s) did not produce a usable result" >&2; exit 1; }
