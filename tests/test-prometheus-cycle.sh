#!/usr/bin/env bash
# Hermetic contract checks for tools/install-prometheus-cycle.sh.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
export HOME="$SB/home"
export OPENCLAW_ARGS_FILE="$SB/openclaw-args"
export FAKE_OPENCLAW_WORKSPACE="$SB/openclaw-workspace"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }
check() {
  desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

mkdir -p "$HOME/.config/borrowedfire" "$SB/prometheus/config" "$SB/prometheus/projects" \
  "$FAKE_OPENCLAW_WORKSPACE"
git init -q "$SB/prometheus"
printf '%s\n' 'journal/*.md merge=union' 'inbox/*.md merge=union' \
  'projects/*.md merge=union' > "$SB/prometheus/.gitattributes"
touch "$SB/prometheus/INDEX.md" "$SB/prometheus/config/fleet.md" "$SB/prometheus/projects/_template.md"
printf '%s\n' "$SB/prometheus" > "$HOME/.config/borrowedfire/brain"
"$SRC/install.sh" --copy --openclaw-workspace "$FAKE_OPENCLAW_WORKSPACE" >/dev/null 2>&1

OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null

check "declares a cron job" grep -qx 'add' "$OPENCLAW_ARGS_FILE"
check "uses stable declaration key" grep -qx 'borrowedfire.prometheus-learning.v1' "$OPENCLAW_ARGS_FILE"
check "uses DST-safe nightly default" grep -qx '35 3 \* \* \*' "$OPENCLAW_ARGS_FILE"
check "uses isolated session" grep -qx 'isolated' "$OPENCLAW_ARGS_FILE"
check "clears stale explicit session keys" grep -qx -- '--clear-session-key' "$OPENCLAW_ARGS_FILE"
check "binds the main agent by default" grep -qx 'main' "$OPENCLAW_ARGS_FILE"
check "creates disabled before alert setup" grep -qx -- '--disabled' "$OPENCLAW_ARGS_FILE"
check "enables only after configuration" grep -qx 'enable' "$OPENCLAW_ARGS_FILE"
check "removes unsupported expect-final flag" bash -c "! grep -qx -- '--expect-final' '$OPENCLAW_ARGS_FILE'"
check "resets stale failure-alert policy" grep -qx -- '--no-failure-alert' "$OPENCLAW_ARGS_FILE"
check "pins failure alerts to announce mode" grep -qx 'announce' "$OPENCLAW_ARGS_FILE"
check "does not pin a model" bash -c "! grep -qx -- '--model' '$OPENCLAW_ARGS_FILE'"
check "does not hide bootstrap context" bash -c "! grep -qx -- '--light-context' '$OPENCLAW_ARGS_FILE'"
check "disables routine delivery" grep -qx -- '--no-deliver' "$OPENCLAW_ARGS_FILE"
check "stores an explicit notification channel" grep -qx 'imessage' "$OPENCLAW_ARGS_FILE"
check "stores an explicit notification destination" grep -qx 'owner-route' "$OPENCLAW_ARGS_FILE"
check "alerts after repeated failures" grep -qx -- '--failure-alert-after' "$OPENCLAW_ARGS_FILE"
check "alerts on skipped runs" grep -qx -- '--failure-alert-include-skipped' "$OPENCLAW_ARGS_FILE"
check "prompt requires namespaced learning mode" grep -q 'borrowedfire-learn skill in fleet mode' "$OPENCLAW_ARGS_FILE"
check "prompt uses binding-scoped watermark" grep -Eq 'notes/openclaw-.+-main-openclaw-workspace-[0-9a-f]{12}-ingest.md' "$OPENCLAW_ARGS_FILE"
check "prompt preserves product mutation boundary" grep -q 'Do not mutate product repositories' "$OPENCLAW_ARGS_FILE"
check "prompt narrows outbox cleanup" grep -q 'exact local-only .brain-outbox/<file>' "$OPENCLAW_ARGS_FILE"
check "prompt permits material digest summary" grep -q 'material-digest summary' "$OPENCLAW_ARGS_FILE"
check "prompt names resolved brain" grep -q "$SB/prometheus" "$OPENCLAW_ARGS_FILE"
check "live route probe sent once" test "$(grep -c '^message$' "$OPENCLAW_ARGS_FILE")" -eq 1
check "route proof persisted privately" test "$(stat -f '%Lp' "$HOME/.config/borrowedfire/prometheus-learning-route.sha256" 2>/dev/null || stat -c '%a' "$HOME/.config/borrowedfire/prometheus-learning-route.sha256")" = 600

OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "matching route is not probed twice" test "$(grep -c '^message$' "$OPENCLAW_ARGS_FILE")" -eq 1

ROUTE_PROOF="$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
rm -f "$ROUTE_PROOF"
mkdir "$ROUTE_PROOF"
rm -f "$OPENCLAW_ARGS_FILE"
if OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "unsafe route-proof target fails closed"
else
  ok "unsafe route-proof target fails closed"
fi
check "unsafe route-proof target disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "unsafe route-proof target is rejected before live probe" bash -c "! grep -qx 'message' '$OPENCLAW_ARGS_FILE'"
rmdir "$ROUTE_PROOF"

mkdir -p "$SB/openclaw-alt"
"$SRC/install.sh" --copy --openclaw-workspace "$SB/openclaw-alt" >/dev/null 2>&1
rm -f "$OPENCLAW_ARGS_FILE"
FAKE_OPENCLAW_ALT_WORKSPACE="$SB/openclaw-alt" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --agent alternate \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "configured alternate agent converges" grep -qx 'alternate' "$OPENCLAW_ARGS_FILE"
check "alternate workspace gets a distinct watermark" grep -Eq 'notes/openclaw-.+-alternate-openclaw-alt-[0-9a-f]{12}-ingest.md' "$OPENCLAW_ARGS_FILE"

FOREIGN_WORKSPACE="$SB/openclaw-foreign"
mkdir -p "$FOREIGN_WORKSPACE/skills/borrowedfire-learn"
printf '%s\n' '---' 'name: borrowedfire-learn' '---' > "$FOREIGN_WORKSPACE/skills/borrowedfire-learn/SKILL.md"
rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_WORKSPACE="$FOREIGN_WORKSPACE" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "unmanaged workspace learning stack fails closed"
else
  ok "unmanaged workspace learning stack fails closed"
fi
check "unmanaged workspace declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"

TAMPERED_WORKSPACE="$SB/openclaw-tampered"
mkdir -p "$TAMPERED_WORKSPACE"
"$SRC/install.sh" --copy --openclaw-workspace "$TAMPERED_WORKSPACE" >/dev/null 2>&1
printf '%s\n' 'tampered instructions' >> "$TAMPERED_WORKSPACE/skills/digest/SKILL.md"
rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_WORKSPACE="$TAMPERED_WORKSPACE" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "tampered managed dependency fails closed"
else
  ok "tampered managed dependency fails closed"
fi
check "tampered dependency declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"
check "tampered dependency disables the existing job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "tampered dependency verifies the disabled job" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

TAMPERED_DOCTRINE_WORKSPACE="$SB/openclaw-tampered-doctrine"
mkdir -p "$TAMPERED_DOCTRINE_WORKSPACE"
"$SRC/install.sh" --copy --openclaw-workspace "$TAMPERED_DOCTRINE_WORKSPACE" >/dev/null 2>&1
sed -i.bak 's/## Borrowed Fire doctrine/## Foreign doctrine/' "$TAMPERED_DOCTRINE_WORKSPACE/AGENTS.md"
rm -f "$TAMPERED_DOCTRINE_WORKSPACE/AGENTS.md.bak" "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_WORKSPACE="$TAMPERED_DOCTRINE_WORKSPACE" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "tampered managed doctrine fails closed"
else
  ok "tampered managed doctrine fails closed"
fi
check "tampered doctrine declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"
check "tampered doctrine disables the existing job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
OUT="$(OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --notify-channel imessage --notify-to owner-route \
  --cron '5 4 * * 0' --tz UTC --dry-run)"
check "dry-run does not invoke OpenClaw" test ! -e "$OPENCLAW_ARGS_FILE"
check "dry-run reports override" grep -q '5 4 \* \* 0.*UTC' <<<"$OUT"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_FAIL_EDIT=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "alert failure fails closed"
else
  ok "alert failure fails closed"
fi
check "alert failure disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "alert failure never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_GET_MISMATCH=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "stored-route mismatch fails closed"
else
  ok "stored-route mismatch fails closed"
fi
check "stored-route mismatch disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "stored-route mismatch never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_STALE_SESSION_KEY=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "stored session-key mismatch fails closed"
else
  ok "stored session-key mismatch fails closed"
fi
check "stored session-key mismatch disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "stored session-key mismatch never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_FAIL_MESSAGE=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "live route failure fails closed"
else
  ok "live route failure fails closed"
fi
check "route failure disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "route failure never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_MESSAGE_NO_ACK=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "missing provider acknowledgement fails closed"
else
  ok "missing provider acknowledgement fails closed"
fi
check "missing acknowledgement disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "missing acknowledgement never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_POISON_ROUTE_PROOF="$HOME/.config/borrowedfire/prometheus-learning-route.sha256" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "post-probe route-proof persistence failure fails closed"
else
  ok "post-probe route-proof persistence failure fails closed"
fi
check "post-probe persistence failure sent the probe" grep -qx 'message' "$OPENCLAW_ARGS_FILE"
check "post-probe persistence failure disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "post-probe persistence failure never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"
rmdir "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_SCHEDULER_DISABLED=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "disabled scheduler fails closed"
else
  ok "disabled scheduler fails closed"
fi
check "disabled scheduler declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_UNKNOWN_AGENT=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --agent typo \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "unknown agent fails closed"
else
  ok "unknown agent fails closed"
fi
check "unknown agent declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"

if OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" >/dev/null 2>&1; then
  fail "missing notification route fails closed"
else
  ok "missing notification route fails closed"
fi

if HOME="$SB/no-brain-home" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "missing brain fails closed"
else
  ok "missing brain fails closed"
fi

git -C "$SB/prometheus" config user.name Fixture
git -C "$SB/prometheus" config user.email fixture@example.invalid
git -C "$SB/prometheus" add .gitattributes INDEX.md config/fleet.md projects/_template.md
git -C "$SB/prometheus" commit -qm init
git -C "$SB/prometheus" worktree add -q -b fixture-worktree "$SB/prometheus-worktree"
OUT="$(OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --brain "$SB/prometheus-worktree" \
  --notify-channel imessage --notify-to owner-route --dry-run)"
check "valid Git worktree brain is accepted" grep -q "$SB/prometheus-worktree" <<<"$OUT"

mkdir -p "$SB/prometheus/subdirectory"
if OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --brain "$SB/prometheus/subdirectory" \
  --notify-channel imessage --notify-to owner-route --dry-run >/dev/null 2>&1; then
  fail "nested Git directory is rejected as a brain root"
else
  ok "nested Git directory is rejected as a brain root"
fi

git init -q "$SB/not-prometheus"
if OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --brain "$SB/not-prometheus" \
  --notify-channel imessage --notify-to owner-route --dry-run >/dev/null 2>&1; then
  fail "arbitrary Git repository is rejected as a brain"
else
  ok "arbitrary Git repository is rejected as a brain"
fi

printf '%s\n' "----" "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
