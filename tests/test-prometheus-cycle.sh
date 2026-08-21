#!/usr/bin/env bash
# Hermetic contract checks for tools/install-prometheus-cycle.sh.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
export HOME="$SB/home"
export XDG_CONFIG_HOME="$HOME/.config"
export OPENCLAW_ARGS_FILE="$SB/openclaw-args"
export FAKE_OPENCLAW_WORKSPACE="$SB/openclaw-workspace"
unset PROMETHEUS_DIR OPENCLAW_HOME OPENCLAW_STATE_DIR OPENCLAW_CONFIG_PATH OPENCLAW_PROFILE
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }
check() {
  desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

recorded_call_count() {
  python3 - "$OPENCLAW_ARGS_FILE" "$@" <<'PY'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
expected = sys.argv[2:]
calls = []
current = []
for line in lines:
    if line == "CALL":
        if current:
            calls.append(current)
        current = []
    else:
        current.append(line)
if current:
    calls.append(current)
print(sum(call == expected for call in calls))
PY
}

mkdir -p "$HOME/.config/borrowedfire" "$SB/prometheus/config" "$SB/prometheus/projects" \
  "$FAKE_OPENCLAW_WORKSPACE"
git init -q "$SB/prometheus"
printf '%s\n' 'journal/*.md merge=union' 'inbox/*.md merge=union' \
  'projects/*.md merge=union' > "$SB/prometheus/.gitattributes"
touch "$SB/prometheus/INDEX.md" "$SB/prometheus/config/fleet.md"
printf '%s\n' "$SB/prometheus" > "$HOME/.config/borrowedfire/brain"
"$SRC/install.sh" --copy --openclaw-workspace "$FAKE_OPENCLAW_WORKSPACE" >/dev/null 2>&1

if OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null; then
  ok "baseline scheduler installation succeeds"
else
  fail "baseline scheduler installation succeeds"
fi

check "declares a cron job" grep -qx 'add' "$OPENCLAW_ARGS_FILE"
check "uses stable declaration key" grep -qx 'borrowedfire.prometheus-learning.v1' "$OPENCLAW_ARGS_FILE"
check "uses DST-safe nightly default" grep -qx '35 3 \* \* \*' "$OPENCLAW_ARGS_FILE"
check "uses isolated session" grep -qx 'isolated' "$OPENCLAW_ARGS_FILE"
check "clears stale explicit session keys" grep -qx -- '--clear-session-key' "$OPENCLAW_ARGS_FILE"
check "binds the main agent by default" grep -qx 'main' "$OPENCLAW_ARGS_FILE"
check "checks effective skill visibility" grep -qx 'skills' "$OPENCLAW_ARGS_FILE"
check "checks skills for the exact agent" grep -qx -- '--agent' "$OPENCLAW_ARGS_FILE"
check "queries the active config path from OpenClaw" grep -qx 'file' "$OPENCLAW_ARGS_FILE"
check "creates disabled before alert setup" grep -qx -- '--disabled' "$OPENCLAW_ARGS_FILE"
check "converges a persistent recurring job" grep -qx -- '--keep-after-run' "$OPENCLAW_ARGS_FILE"
check "enables only after configuration" grep -qx 'enable' "$OPENCLAW_ARGS_FILE"
check "removes unsupported expect-final flag" bash -c "! grep -qx -- '--expect-final' '$OPENCLAW_ARGS_FILE'"
check "resets stale failure-alert policy" grep -qx -- '--no-failure-alert' "$OPENCLAW_ARGS_FILE"
check "pins failure alerts to announce mode" grep -qx 'announce' "$OPENCLAW_ARGS_FILE"
check "does not pin a model" bash -c "! grep -qx -- '--model' '$OPENCLAW_ARGS_FILE'"
check "does not hide bootstrap context" bash -c "! grep -qx -- '--light-context' '$OPENCLAW_ARGS_FILE'"
check "does not suppress skill loading with a payload tool allowlist" \
  bash -c "! grep -qx -- '--tools' '$OPENCLAW_ARGS_FILE'"
check "clears stale payload tool allowlists" grep -qx -- '--clear-tools' "$OPENCLAW_ARGS_FILE"
check "disables routine delivery" grep -qx -- '--no-deliver' "$OPENCLAW_ARGS_FILE"
check "stores an explicit notification channel" grep -qx 'imessage' "$OPENCLAW_ARGS_FILE"
check "stores an explicit notification destination" grep -qx 'owner-route' "$OPENCLAW_ARGS_FILE"
check "pins the resolved account on job delivery and the live probe" \
  test "$(grep -c '^--account$' "$OPENCLAW_ARGS_FILE")" -eq 3
check "pins the resolved account on failure alerts" \
  grep -qx -- '--failure-alert-account-id' "$OPENCLAW_ARGS_FILE"
check "alerts after repeated failures" grep -qx -- '--failure-alert-after' "$OPENCLAW_ARGS_FILE"
check "alerts on skipped runs" grep -qx -- '--failure-alert-include-skipped' "$OPENCLAW_ARGS_FILE"
check "prompt requires namespaced learning mode" grep -q 'borrowedfire-learn skill in fleet mode' "$OPENCLAW_ARGS_FILE"
check "prompt uses binding-scoped watermark" grep -Eq 'notes/openclaw-.+-main-openclaw-workspace-[0-9a-f]{12}-ingest.md' "$OPENCLAW_ARGS_FILE"
check "prompt defines prospective first-run behavior" \
  grep -q 'do not backfill pre-existing session notes' "$OPENCLAW_ARGS_FILE"
check "prompt preserves product mutation boundary" grep -q 'Do not mutate product repositories' "$OPENCLAW_ARGS_FILE"
check "prompt narrows outbox cleanup" grep -q 'exact local-only .brain-outbox/<file>' "$OPENCLAW_ARGS_FILE"
check "prompt permits material digest summary" grep -q 'material-digest summary' "$OPENCLAW_ARGS_FILE"
check "prompt names resolved brain" grep -q "$SB/prometheus" "$OPENCLAW_ARGS_FILE"
check "gateway route probe ran once" test "$(recorded_call_count cron run route-probe-job --wait --wait-timeout 2m --poll-interval 1s)" -eq 1
check "gateway route probe uses a disabled transient declaration" \
  grep -qx 'borrowedfire.prometheus-learning.route-proof.v1' "$OPENCLAW_ARGS_FILE"
check "gateway route probe uses a command payload" grep -qx -- '--command-argv' "$OPENCLAW_ARGS_FILE"
check "gateway route probe is removed after delivery" test "$(recorded_call_count cron rm route-probe-job)" -eq 1
check "route proof persisted privately" test "$(stat -c '%a' "$HOME/.config/borrowedfire/prometheus-learning-route.sha256" 2>/dev/null || stat -f '%Lp' "$HOME/.config/borrowedfire/prometheus-learning-route.sha256" 2>/dev/null)" = 600

rm -f "$OPENCLAW_ARGS_FILE"
FAKE_OPENCLAW_LEGACY_CLEAR_TOOLS=1 \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "legacy null clear-tools representation converges" grep -qx 'enable' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_RESTRICTED_TOOLS=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "restrictive payload tool allowlist fails closed"
else
  ok "restrictive payload tool allowlist fails closed"
fi
check "restrictive payload tool allowlist disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_SKILLS_HIDDEN=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "agent-hidden learning skill fails closed"
else
  ok "agent-hidden learning skill fails closed"
fi
check "hidden learning skill declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"
check "hidden learning skill disables the stale declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "hidden learning skill verifies the stale declaration" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "matching stored route is re-probed on installer convergence" \
  test "$(recorded_call_count cron run route-probe-job --wait --wait-timeout 2m --poll-interval 1s)" -eq 1

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
FAKE_OPENCLAW_BINDINGS='[{"agentId":"main","match":{"channel":"imessage","accountId":"ops"},"description":"imessage account=ops"}]' \
  FAKE_OPENCLAW_CHANNEL_STATUS='{"channelDefaultAccountId":{"imessage":"default"},"channelAccounts":{"imessage":[{"accountId":"default","configured":true,"enabled":true},{"accountId":"ops","configured":true,"enabled":true}]}}' \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "selected agent binding pins one account across job, alert, and probe" \
  test "$(grep -c '^ops$' "$OPENCLAW_ARGS_FILE")" -eq 4
check "selected agent account route receives the live proof" grep -qx 'run' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
FAKE_OPENCLAW_BINDINGS='[{"agentId":"main","match":{"channel":"imessage","accountId":"ops"},"description":"imessage account=ops"},{"agentId":"main","match":{"channel":"imessage","accountId":"audit","peer":{"kind":"direct","id":"owner-route"}},"description":"imessage account=audit peer=direct:owner-route"}]' \
  FAKE_OPENCLAW_CHANNEL_STATUS='{"channelDefaultAccountId":{"imessage":"default"},"channelAccounts":{"imessage":[{"accountId":"default","configured":true,"enabled":true},{"accountId":"ops","configured":true,"enabled":true},{"accountId":"audit","configured":true,"enabled":true}]}}' \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "ambiguous or scoped bindings use the runtime default account" \
  test "$(grep -c '^default$' "$OPENCLAW_ARGS_FILE")" -eq 4
check "ambiguous bindings do not select the first account" \
  bash -c "! grep -qx 'ops' '$OPENCLAW_ARGS_FILE'"

rm -f "$OPENCLAW_ARGS_FILE"
FAKE_OPENCLAW_STALE_DELETE_AFTER_RUN=1 \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "stale one-shot deletion state is cleared" grep -qx -- '--keep-after-run' "$OPENCLAW_ARGS_FILE"

PHYSICAL_SRC="$(cd "$SRC" && pwd -P)"
ln -s "$PHYSICAL_SRC" "$SB/source-alias"
mkdir -p "$SB/openclaw-symlink-install"
"$SB/source-alias/install.sh" --openclaw-workspace "$SB/openclaw-symlink-install" >/dev/null 2>&1
check "symlink-invoked installer records canonical skill targets" \
  test "$(readlink "$SB/openclaw-symlink-install/skills/borrowedfire-learn")" = \
  "$PHYSICAL_SRC/skills/borrowedfire-learn"
rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_WORKSPACE="$SB/openclaw-symlink-install" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SB/source-alias/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null; then
  ok "symlink-invoked scheduler installation succeeds"
else
  fail "symlink-invoked scheduler installation succeeds"
fi
check "scheduler accepts a symlink-invoked installer deployment" grep -qx 'enable' "$OPENCLAW_ARGS_FILE"

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
check "unsafe route-proof target is rejected before live probe" bash -c "! grep -qx 'run' '$OPENCLAW_ARGS_FILE'"
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
check "agent change disables the prior declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "agent change removes the prior declaration" grep -qx 'rm' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
FAKE_OPENCLAW_DUPLICATE_DECLARATIONS=1 \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "duplicate declarations are both disabled" \
  test "$(recorded_call_count cron disable duplicate-job)" -eq 1
check "duplicate declarations are both removed" \
  test "$(recorded_call_count cron rm duplicate-job)" -eq 1
check "duplicate declaration cleanup converges one replacement" \
  test "$(grep -c '^borrowedfire.prometheus-learning.v1$' "$OPENCLAW_ARGS_FILE")" -eq 1

mkdir -p "$SB/host-one-bin" "$SB/host-two-bin"
# shellcheck disable=SC2016  # write a literal fixture script that expands its own argument
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "-f" ]; then printf "%s\\n" controller-one.example; else printf "%s\\n" shared; fi' \
  > "$SB/host-one-bin/hostname"
# shellcheck disable=SC2016  # write a literal fixture script that expands its own argument
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "-f" ]; then printf "%s\\n" controller-two.example; else printf "%s\\n" shared; fi' \
  > "$SB/host-two-bin/hostname"
chmod +x "$SB/host-one-bin/hostname" "$SB/host-two-bin/hostname"
rm -f "$OPENCLAW_ARGS_FILE"
PATH="$SB/host-one-bin:$PATH" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
HOST_ONE_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$OPENCLAW_ARGS_FILE" | head -1)"
rm -f "$OPENCLAW_ARGS_FILE"
PATH="$SB/host-two-bin:$PATH" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
HOST_TWO_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$OPENCLAW_ARGS_FILE" | head -1)"
check "same-short-name controllers get distinct watermarks" \
  test -n "$HOST_ONE_WATERMARK" -a -n "$HOST_TWO_WATERMARK" -a \
  "$HOST_ONE_WATERMARK" != "$HOST_TWO_WATERMARK"

OPENCLAW_ARGS_FILE="$SB/state-a-args" OPENCLAW_STATE_DIR="$SB/controller-state-a" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
OPENCLAW_ARGS_FILE="$SB/state-b-args" OPENCLAW_STATE_DIR="$SB/controller-state-b" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
STATE_A_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/state-a-args" | head -1)"
STATE_B_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/state-b-args" | head -1)"
check "distinct OpenClaw state roots get distinct watermarks" \
  test -n "$STATE_A_WATERMARK" -a -n "$STATE_B_WATERMARK" -a \
  "$STATE_A_WATERMARK" != "$STATE_B_WATERMARK"

OPENCLAW_ARGS_FILE="$SB/config-a-args" OPENCLAW_CONFIG_PATH="$SB/config-a.json" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
OPENCLAW_ARGS_FILE="$SB/config-b-args" OPENCLAW_CONFIG_PATH="$SB/config-b.json" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
CONFIG_A_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/config-a-args" | head -1)"
CONFIG_B_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/config-b-args" | head -1)"
check "distinct OpenClaw config paths get distinct watermarks" \
  test -n "$CONFIG_A_WATERMARK" -a -n "$CONFIG_B_WATERMARK" -a \
  "$CONFIG_A_WATERMARK" != "$CONFIG_B_WATERMARK"

LEGACY_CONFIG_HOME="$SB/legacy-config-home"
mkdir -p "$LEGACY_CONFIG_HOME/.openclaw"
mkdir -p "$LEGACY_CONFIG_HOME/.clawdbot"
printf '%s\n' '{}' > "$LEGACY_CONFIG_HOME/.clawdbot/clawdbot.json"
# shellcheck disable=SC2016  # The fixture must emit OpenClaw's literal display prefix.
OPENCLAW_ARGS_FILE="$SB/legacy-config-args" OPENCLAW_HOME="$LEGACY_CONFIG_HOME" \
  FAKE_OPENCLAW_CONFIG_FILE_OUTPUT="$(printf '%s\n%s' 'Doctor notice' '$OPENCLAW_HOME/.clawdbot/clawdbot.json')" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
LEGACY_CONFIG_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/legacy-config-args" | head -1)"
printf '%s\n' '{}' > "$LEGACY_CONFIG_HOME/.openclaw/openclaw.json"
OPENCLAW_ARGS_FILE="$SB/canonical-config-args" OPENCLAW_HOME="$LEGACY_CONFIG_HOME" \
  FAKE_OPENCLAW_CONFIG_FILE="$LEGACY_CONFIG_HOME/.openclaw/openclaw.json" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
CANONICAL_CONFIG_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/canonical-config-args" | head -1)"
check "active legacy config path gets its own controller watermark" \
  test -n "$LEGACY_CONFIG_WATERMARK" -a -n "$CANONICAL_CONFIG_WATERMARK" -a \
  "$LEGACY_CONFIG_WATERMARK" != "$CANONICAL_CONFIG_WATERMARK"
check "diagnostic lines before the active config path are tolerated" \
  grep -qx 'run' "$SB/legacy-config-args"
check "OpenClaw home display prefix resolves to the effective home" \
  test -n "$LEGACY_CONFIG_WATERMARK"
check "legacy-to-canonical config migration requires a fresh route probe" \
  grep -qx 'run' "$SB/canonical-config-args"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_CONFIG_FILE_OUTPUT='not-a-path' \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "invalid active config path fails closed"
else
  ok "invalid active config path fails closed"
fi
check "invalid active config path disables the stale declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "invalid active config path never declares a replacement" \
  bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"

CONFIG_DIGEST_PATH="$SB/controller-config.json"
# shellcheck disable=SC2016  # $include is an intentional literal OpenClaw config key
printf '%s\n' '{"$include":"./channel-config.json"}' > "$CONFIG_DIGEST_PATH"
CONFIG_ROOT_DIGEST="$(git hash-object "$CONFIG_DIGEST_PATH")"
OPENCLAW_ARGS_FILE="$SB/config-digest-one-args" OPENCLAW_CONFIG_PATH="$CONFIG_DIGEST_PATH" \
  FAKE_OPENCLAW_CHANNEL_CONFIG='{"defaultAccount":"one"}' \
  FAKE_OPENCLAW_CHANNEL_STATUS='{"channelDefaultAccountId":{"imessage":"one"},"channelAccounts":{"imessage":[{"accountId":"one","configured":true,"enabled":true}]}}' \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
OPENCLAW_ARGS_FILE="$SB/config-digest-two-args" OPENCLAW_CONFIG_PATH="$CONFIG_DIGEST_PATH" \
  FAKE_OPENCLAW_CHANNEL_CONFIG='{"defaultAccount":"two"}' \
  FAKE_OPENCLAW_CHANNEL_STATUS='{"channelDefaultAccountId":{"imessage":"two"},"channelAccounts":{"imessage":[{"accountId":"two","configured":true,"enabled":true}]}}' \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "resolved include or environment config changes require a fresh route probe" \
  grep -qx 'run' "$SB/config-digest-two-args"
check "effective-config proof does not depend on root config bytes changing" \
  test "$(git hash-object "$CONFIG_DIGEST_PATH")" = "$CONFIG_ROOT_DIGEST"

OPENCLAW_ARGS_FILE="$SB/profile-a-args" OPENCLAW_PROFILE="profile-a" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
OPENCLAW_ARGS_FILE="$SB/profile-b-args" OPENCLAW_PROFILE="profile-b" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
PROFILE_A_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/profile-a-args" | head -1)"
PROFILE_B_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$SB/profile-b-args" | head -1)"
check "distinct OpenClaw profiles get distinct watermarks" \
  test -n "$PROFILE_A_WATERMARK" -a -n "$PROFILE_B_WATERMARK" -a \
  "$PROFILE_A_WATERMARK" != "$PROFILE_B_WATERMARK"
check "distinct OpenClaw profiles require independent route probes" \
  grep -qx 'run' "$SB/profile-a-args"
check "second OpenClaw profile does not reuse the first route proof" \
  grep -qx 'run' "$SB/profile-b-args"

mkdir -p "$SB/machine-fallback-bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$SB/machine-fallback-bin/ioreg"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$SB/machine-fallback-bin/sysctl"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" fallback-machine-id' \
  > "$SB/machine-fallback-bin/hostid"
chmod +x "$SB/machine-fallback-bin/ioreg" "$SB/machine-fallback-bin/sysctl" \
  "$SB/machine-fallback-bin/hostid"
rm -f "$OPENCLAW_ARGS_FILE"
if PATH="$SB/machine-fallback-bin:$PATH" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null; then
  ok "machine identity falls through failed candidate commands"
else
  fail "machine identity falls through failed candidate commands"
fi

LONG_COMPONENT="$(printf '%200s' '' | tr ' ' w)"
LONG_WORKSPACE="$SB/$LONG_COMPONENT"
LONG_HOST_BIN="$SB/long-host-bin"
mkdir -p "$LONG_WORKSPACE" "$LONG_HOST_BIN"
"$SRC/install.sh" --copy --openclaw-workspace "$LONG_WORKSPACE" >/dev/null 2>&1
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%063d.%063d.%063d.%061d\\n" 0 0 0 0 | tr "0" h' \
  > "$LONG_HOST_BIN/hostname"
chmod +x "$LONG_HOST_BIN/hostname"
rm -f "$OPENCLAW_ARGS_FILE"
FAKE_OPENCLAW_WORKSPACE="$LONG_WORKSPACE" PATH="$LONG_HOST_BIN:$PATH" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
LONG_WATERMARK="$(grep -Eo 'notes/openclaw-[^ ]+-ingest\.md' "$OPENCLAW_ARGS_FILE" | head -1)"
check "watermark basename stays below the portable safety bound" \
  test "$(printf '%s' "${LONG_WATERMARK##*/}" | wc -c | tr -d ' ')" -le 240
check "bounded watermark retains binding hash" \
  grep -Eq '^notes/openclaw-.+-[0-9a-f]{12}-ingest\.md$' <<<"$LONG_WATERMARK"

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

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_POST_ENABLE_MISMATCH=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "post-enable configuration drift fails closed"
else
  ok "post-enable configuration drift fails closed"
fi
check "post-enable drift attempts enable" grep -qx 'enable' "$OPENCLAW_ARGS_FILE"
check "post-enable drift is disabled" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if OUT="$(FAKE_OPENCLAW_POST_ENABLE_MISMATCH=1 FAKE_OPENCLAW_FAIL_DISABLE=1 \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route 2>&1)"; then
  fail "unverifiable post-enable disable fails closed"
else
  ok "unverifiable post-enable disable fails closed"
fi
check "failed disable is not reported as safe" grep -q 'could not be proven disabled' <<<"$OUT"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_FAIL_ENABLE_AFTER_COMMIT=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "ambiguous enable response fails closed"
else
  ok "ambiguous enable response fails closed"
fi
check "ambiguous enable is followed by disable" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "ambiguous enable verifies disabled state" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_FAIL_PROBE_RUN=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "gateway route-run failure fails closed"
else
  ok "gateway route-run failure fails closed"
fi
check "route-run failure disables the learning job" \
  test "$(recorded_call_count cron disable fixture-job)" -ge 1
check "route-run failure disables the temporary probe" \
  test "$(recorded_call_count cron disable route-probe-job)" -ge 1
check "route-run failure never enables the job" \
  test "$(recorded_call_count cron enable fixture-job)" -eq 0

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_PROBE_INCOMPLETE=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "incomplete gateway route run fails closed"
else
  ok "incomplete gateway route run fails closed"
fi
check "incomplete route run disables the learning job" \
  test "$(recorded_call_count cron disable fixture-job)" -ge 1
check "incomplete route run stores no route proof" \
  test ! -e "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_PROBE_NOT_DELIVERED=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "non-delivered gateway route run fails closed"
else
  ok "non-delivered gateway route run fails closed"
fi
check "non-delivered route run disables the learning job" \
  test "$(recorded_call_count cron disable fixture-job)" -ge 1
check "non-delivered route run never enables the job" \
  test "$(recorded_call_count cron enable fixture-job)" -eq 0
check "non-delivered route run stores no route proof" \
  test ! -e "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_PROBE_ERROR=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "errored gateway route run fails closed"
else
  ok "errored gateway route run fails closed"
fi
check "errored route run disables the learning job" \
  test "$(recorded_call_count cron disable fixture-job)" -ge 1
check "errored route run never enables the job" \
  test "$(recorded_call_count cron enable fixture-job)" -eq 0
check "errored route run stores no route proof" \
  test ! -e "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"

rm -f "$OPENCLAW_ARGS_FILE" "$HOME/.config/borrowedfire/prometheus-learning-route.sha256"
if FAKE_OPENCLAW_POISON_ROUTE_PROOF="$HOME/.config/borrowedfire/prometheus-learning-route.sha256" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "post-probe route-proof persistence failure fails closed"
else
  ok "post-probe route-proof persistence failure fails closed"
fi
check "post-probe persistence failure ran the gateway probe" grep -qx 'run' "$OPENCLAW_ARGS_FILE"
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
check "disabled scheduler disables the stale declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "disabled scheduler verifies the stale declaration" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_FAIL_STATUS=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "unreadable scheduler status fails closed"
else
  ok "unreadable scheduler status fails closed"
fi
check "unreadable scheduler status disables the stale declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "unreadable scheduler status verifies the stale declaration" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_FAIL_ADD=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "failed declaration convergence fails closed"
else
  ok "failed declaration convergence fails closed"
fi
check "failed declaration convergence disables the stale declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "failed declaration convergence verifies the stale declaration" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_ADD_NO_ID=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "unparseable declaration response fails closed"
else
  ok "unparseable declaration response fails closed"
fi
check "unparseable declaration response disables the stale declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "unparseable declaration response verifies the stale declaration" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_UNKNOWN_AGENT=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "removed configured agent fails closed"
else
  ok "removed configured agent fails closed"
fi
check "removed configured agent declares no job" bash -c "! grep -qx 'add' '$OPENCLAW_ARGS_FILE'"
check "removed configured agent disables its stale job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "removed configured agent verifies the disabled job" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_FAIL_AGENTS_LIST=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "unreadable agent configuration fails closed"
else
  ok "unreadable agent configuration fails closed"
fi
check "unreadable agent configuration disables the declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"

rm -f "$OPENCLAW_ARGS_FILE"
if OUT="$(FAKE_OPENCLAW_FAIL_AGENTS_LIST=1 FAKE_OPENCLAW_LIST_TRUNCATED=1 \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route 2>&1)"; then
  fail "truncated cleanup listing fails closed"
else
  ok "truncated cleanup listing fails closed"
fi
check "truncated cleanup never claims the hidden declaration is absent" \
  grep -q 'could not be proven disabled' <<<"$OUT"
check "truncated cleanup does not disable an unrelated visible job" \
  bash -c "! grep -qx 'disable' '$OPENCLAW_ARGS_FILE'"

INVALID_ALT_WORKSPACE="$SB/openclaw-invalid-alternate"
mkdir -p "$INVALID_ALT_WORKSPACE"
rm -f "$OPENCLAW_ARGS_FILE"
if FAKE_OPENCLAW_ALT_WORKSPACE="$INVALID_ALT_WORKSPACE" \
  OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" --agent alternate \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "agent-change validation failure fails closed"
else
  ok "agent-change validation failure fails closed"
fi
check "agent-change failure disables the declaration-key job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"

if OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" >/dev/null 2>&1; then
  fail "missing notification route fails closed"
else
  ok "missing notification route fails closed"
fi

rm -f "$OPENCLAW_ARGS_FILE"
if HOME="$SB/no-brain-home" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "missing brain fails closed"
else
  ok "missing brain fails closed"
fi
check "missing brain disables the existing declaration" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "missing brain verifies the disabled declaration" grep -qx 'get' "$OPENCLAW_ARGS_FILE"

git -C "$SB/prometheus" config user.name Fixture
git -C "$SB/prometheus" config user.email fixture@example.invalid
git -C "$SB/prometheus" add .gitattributes INDEX.md config/fleet.md
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
