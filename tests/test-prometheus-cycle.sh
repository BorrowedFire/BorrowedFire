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
check "does not pin a model" bash -c "! grep -qx -- '--model' '$OPENCLAW_ARGS_FILE'"
check "disables routine delivery" grep -qx -- '--no-deliver' "$OPENCLAW_ARGS_FILE"
check "prompt requires learn fleet mode" grep -q 'learn skill in fleet mode' "$OPENCLAW_ARGS_FILE"
check "prompt forbids product mutation" grep -q 'Do not mutate product repositories' "$OPENCLAW_ARGS_FILE"
check "prompt names resolved brain" grep -q "$SB/prometheus" "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
OUT="$(OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --cron '5 4 * * 0' --tz UTC --dry-run)"
check "dry-run does not invoke OpenClaw" test ! -e "$OPENCLAW_ARGS_FILE"
check "dry-run reports override" grep -q '5 4 \* \* 0.*UTC' <<<"$OUT"

if HOME="$SB/no-brain-home" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" >/dev/null 2>&1; then
  fail "missing brain fails closed"
else
  ok "missing brain fails closed"
fi

printf '%s\n' "----" "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
