#!/usr/bin/env bash
# Hermetic contract checks for tools/install-prometheus-cycle.sh.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
export HOME="$SB/home"
export XDG_CONFIG_HOME="$HOME/.config"
export OPENCLAW_ARGS_FILE="$SB/openclaw-args"
export FAKE_OPENCLAW_WORKSPACE="$SB/openclaw-workspace"
unset PROMETHEUS_DIR OPENCLAW_HOME
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
check "creates disabled before alert setup" grep -qx -- '--disabled' "$OPENCLAW_ARGS_FILE"
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
check "alerts after repeated failures" grep -qx -- '--failure-alert-after' "$OPENCLAW_ARGS_FILE"
check "alerts on skipped runs" grep -qx -- '--failure-alert-include-skipped' "$OPENCLAW_ARGS_FILE"
check "prompt requires namespaced learning mode" grep -q 'borrowedfire-learn skill in fleet mode' "$OPENCLAW_ARGS_FILE"
check "prompt uses binding-scoped watermark" grep -Eq 'notes/openclaw-.+-main-openclaw-workspace-[0-9a-f]{12}-ingest.md' "$OPENCLAW_ARGS_FILE"
check "prompt preserves product mutation boundary" grep -q 'Do not mutate product repositories' "$OPENCLAW_ARGS_FILE"
check "prompt narrows outbox cleanup" grep -q 'exact local-only .brain-outbox/<file>' "$OPENCLAW_ARGS_FILE"
check "prompt permits material digest summary" grep -q 'material-digest summary' "$OPENCLAW_ARGS_FILE"
check "prompt names resolved brain" grep -q "$SB/prometheus" "$OPENCLAW_ARGS_FILE"
check "live route probe sent once" test "$(grep -c '^message$' "$OPENCLAW_ARGS_FILE")" -eq 1
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
OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null
check "matching route is not probed twice" bash -c "! grep -qx 'message' '$OPENCLAW_ARGS_FILE'"

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
if FAKE_OPENCLAW_MESSAGE_ERROR_WITH_ACK=1 OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "explicit provider error with acknowledgement fails closed"
else
  ok "explicit provider error with acknowledgement fails closed"
fi
check "provider error with acknowledgement disables the job" grep -qx 'disable' "$OPENCLAW_ARGS_FILE"
check "provider error with acknowledgement never enables the job" bash -c "! grep -qx 'enable' '$OPENCLAW_ARGS_FILE'"
check "provider error with acknowledgement stores no route proof" \
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

if HOME="$SB/no-brain-home" OPENCLAW_BIN="$SRC/tests/fixtures/fake-openclaw.sh" \
  "$SRC/tools/install-prometheus-cycle.sh" \
  --notify-channel imessage --notify-to owner-route >/dev/null 2>&1; then
  fail "missing brain fails closed"
else
  ok "missing brain fails closed"
fi

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
