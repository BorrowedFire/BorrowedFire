#!/usr/bin/env bash
# Hermetic contract checks for tools/install-prometheus-cycle.sh.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
export HOME="$SB/home"
export OPENCLAW_ARGS_FILE="$SB/openclaw-args"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }
check() {
  desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

mkdir -p "$HOME/.config/borrowedfire" "$SB/prometheus/.git"
printf '%s\n' "$SB/prometheus" > "$HOME/.config/borrowedfire/brain"

OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" >/dev/null

check "declares a cron job" grep -qx 'add' "$OPENCLAW_ARGS_FILE"
check "uses stable declaration key" grep -qx 'borrowedfire.prometheus-learning.v1' "$OPENCLAW_ARGS_FILE"
check "uses nightly default" grep -qx '35 2 \* \* \*' "$OPENCLAW_ARGS_FILE"
check "uses isolated session" grep -qx 'isolated' "$OPENCLAW_ARGS_FILE"
check "binds the main agent by default" grep -qx 'main' "$OPENCLAW_ARGS_FILE"
check "creates disabled before alert setup" grep -qx -- '--disabled' "$OPENCLAW_ARGS_FILE"
check "enables only after configuration" grep -qx 'enable' "$OPENCLAW_ARGS_FILE"
check "does not pin a model" bash -c "! grep -qx -- '--model' '$OPENCLAW_ARGS_FILE'"
check "does not hide bootstrap context" bash -c "! grep -qx -- '--light-context' '$OPENCLAW_ARGS_FILE'"
check "disables routine delivery" grep -qx -- '--no-deliver' "$OPENCLAW_ARGS_FILE"
check "alerts after repeated failures" grep -qx -- '--failure-alert-after' "$OPENCLAW_ARGS_FILE"
check "alerts on skipped runs" grep -qx -- '--failure-alert-include-skipped' "$OPENCLAW_ARGS_FILE"
check "uses the last owner route by default" grep -qx 'last' "$OPENCLAW_ARGS_FILE"
check "prompt requires learn fleet mode" grep -q 'learn skill in fleet mode' "$OPENCLAW_ARGS_FILE"
check "prompt forbids product mutation" grep -q 'Do not mutate product repositories' "$OPENCLAW_ARGS_FILE"
check "prompt names resolved brain" grep -q "$SB/prometheus" "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
OUT="$(OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --cron '5 4 * * 0' --tz UTC --dry-run)"
check "dry-run does not invoke OpenClaw" test ! -e "$OPENCLAW_ARGS_FILE"
check "dry-run reports override" grep -q '5 4 \* \* 0.*UTC' <<<"$OUT"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_FAIL_EDIT=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" >/dev/null 2>&1; then
  fail "alert failure fails closed"
else
  ok "alert failure fails closed"
fi
check "alert failure disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "alert failure never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"

if HOME="$SB/no-brain-home" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" >/dev/null 2>&1; then
  fail "missing brain fails closed"
else
  ok "missing brain fails closed"
fi

printf '%s\n' "----" "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
