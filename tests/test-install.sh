#!/usr/bin/env bash
# Sandbox verification for install.sh. Runs against a fake HOME.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
export HOME="$SB/home"
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

unset CODEX_HOME   # hermetic: the runner's Codex root must not leak in
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.qwen" "$SB/openclaw-ws"

# --- 1. fresh install across all four harnesses ---
"$SRC/install.sh" --openclaw-workspace "$SB/openclaw-ws" >/dev/null 2>&1
check "claude: remember linked"        test -L "$HOME/.claude/skills/remember"
check "codex: land linked"             test -L "$HOME/.codex/skills/land"
check "qwen: maintainer linked"        test -L "$HOME/.qwen/skills/maintainer"
check "openclaw: digest linked"        test -L "$SB/openclaw-ws/skills/digest"
check "claude: manifest written"       grep -q '^remember link$' "$HOME/.claude/skills/.borrowedfire-manifest"
check "claude: doctrine block present" grep -q 'BEGIN BORROWEDFIRE DOCTRINE' "$HOME/.claude/CLAUDE.md"
check "openclaw: doctrine in AGENTS.md" grep -q 'BEGIN BORROWEDFIRE DOCTRINE' "$SB/openclaw-ws/AGENTS.md"
check "manifest has 14 entries"        test "$(wc -l < "$HOME/.claude/skills/.borrowedfire-manifest")" -eq 14

# --- 2. idempotence: re-run, doctrine block appears exactly once ---
"$SRC/install.sh" --openclaw-workspace "$SB/openclaw-ws" >/dev/null 2>&1
check "doctrine idempotent (1 block)"  test "$(grep -c 'BEGIN BORROWEDFIRE DOCTRINE' "$HOME/.claude/CLAUDE.md")" -eq 1
check "still 14 manifest entries"      test "$(wc -l < "$HOME/.claude/skills/.borrowedfire-manifest")" -eq 14

# --- 3. legacy unowned dir warns, --adopt retires it ---
mkdir -p "$HOME/.codex/skills/takeoff"; echo x > "$HOME/.codex/skills/takeoff/SKILL.md"
OUT="$("$SRC/install.sh" 2>&1)"
check "legacy takeoff warned"          grep -q 'WARN.*takeoff' <<<"$OUT"
check "legacy takeoff untouched"       test -d "$HOME/.codex/skills/takeoff"
"$SRC/install.sh" --adopt >/dev/null 2>&1
check "adopt retires takeoff"          test ! -e "$HOME/.codex/skills/takeoff"
check "takeoff backed up"              bash -c "ls '$HOME/.codex/skills/.borrowedfire-backup/' | grep -q '^takeoff\.'"

# --- 4. unowned same-name collision skipped, --adopt replaces ---
rm "$HOME/.qwen/skills/recall"
mkdir -p "$HOME/.qwen/skills/recall"; echo mine > "$HOME/.qwen/skills/recall/SKILL.md"
# de-own it in the manifest to simulate a pre-existing user skill
grep -v '^recall ' "$HOME/.qwen/skills/.borrowedfire-manifest" > "$SB/m" && mv "$SB/m" "$HOME/.qwen/skills/.borrowedfire-manifest"
OUT="$("$SRC/install.sh" 2>&1)"
check "unowned recall skipped"         grep -q 'SKIP.*recall' <<<"$OUT"
check "unowned recall content intact"  grep -q mine "$HOME/.qwen/skills/recall/SKILL.md"
"$SRC/install.sh" --adopt >/dev/null 2>&1
check "adopt replaces recall w/ link"  test -L "$HOME/.qwen/skills/recall"
check "old recall backed up"           bash -c "ls '$HOME/.qwen/skills/.borrowedfire-backup/' | grep -q '^recall\.'"

# --- 5. manifest-owned stale entry pruned (rename scenario) ---
mkdir -p "$HOME/.claude/skills/blackbox"; echo x > "$HOME/.claude/skills/blackbox/SKILL.md"
touch "$HOME/.claude/skills/blackbox/.borrowedfire-copy"   # simulate an installer-made copy
echo "blackbox copy" >> "$HOME/.claude/skills/.borrowedfire-manifest"
"$SRC/install.sh" >/dev/null 2>&1
check "stale blackbox pruned"          test ! -e "$HOME/.claude/skills/blackbox"
check "blackbox gone from manifest"    bash -c "! grep -q '^blackbox' '$HOME/.claude/skills/.borrowedfire-manifest'"

# --- 6. --copy mode ---
rm -rf "$HOME/.qwen/skills" && mkdir -p "$HOME/.qwen/skills"
"$SRC/install.sh" --copy >/dev/null 2>&1
check "copy mode: real dir"            test -d "$HOME/.qwen/skills/ship" -a ! -L "$HOME/.qwen/skills/ship"
check "copy mode: manifest says copy"  grep -q '^ship copy$' "$HOME/.qwen/skills/.borrowedfire-manifest"
check "copy: references included"      test -f "$HOME/.qwen/skills/remember/references/brain-schema.md"

# --- 7. brain pointer ---
mkdir -p "$HOME/prometheus/.git"
"$SRC/install.sh" >/dev/null 2>&1
check "brain pointer auto-written"     grep -q "$HOME/prometheus" "$HOME/.config/borrowedfire/brain"
rm -f "$HOME/.config/borrowedfire/brain"; rm -rf "$HOME/prometheus"
mkdir -p "$HOME/bfbrain/.git"
"$SRC/install.sh" >/dev/null 2>&1
check "legacy bfbrain still detected"  grep -q "$HOME/bfbrain" "$HOME/.config/borrowedfire/brain"
rm -rf "$HOME/bfbrain"; rm -f "$HOME/.config/borrowedfire/brain"
mkdir -p "$SB/custom-brain/.git"
BFBRAIN_DIR="$SB/custom-brain" "$SRC/install.sh" >/dev/null 2>&1
check "legacy env var migrated"        grep -q "$SB/custom-brain" "$HOME/.config/borrowedfire/brain"
rm -f "$HOME/.config/borrowedfire/brain"
mkdir -p "$HOME/prometheus/.git"
"$SRC/install.sh" >/dev/null 2>&1

# --- 8. uninstall: removes owned, leaves unowned, strips doctrine ---
mkdir -p "$HOME/.claude/skills/my-own-skill"; echo mine > "$HOME/.claude/skills/my-own-skill/SKILL.md"
"$SRC/install.sh" --uninstall >/dev/null 2>&1
check "uninstall removes owned"        test ! -e "$HOME/.claude/skills/remember"
check "uninstall leaves unowned"       test -d "$HOME/.claude/skills/my-own-skill"
check "uninstall strips doctrine"      bash -c "! grep -q 'BORROWEDFIRE DOCTRINE' '$HOME/.claude/CLAUDE.md'"
check "uninstall removes manifest"     test ! -f "$HOME/.claude/skills/.borrowedfire-manifest"

# --- 8b. --copy converts an existing linked install (Codex P2 #3) ---
mkdir -p "$HOME/.codex"
"$SRC/install.sh" >/dev/null 2>&1
check "pre-convert: land is a link"    test -L "$HOME/.codex/skills/land"
"$SRC/install.sh" --copy >/dev/null 2>&1
check "convert: land is a real dir"    bash -c "test -d '$HOME/.codex/skills/land' && ! test -L '$HOME/.codex/skills/land'"
check "convert: manifest says copy"    grep -q '^land copy$' "$HOME/.codex/skills/.borrowedfire-manifest"
"$SRC/install.sh" >/dev/null 2>&1
check "no flip-flop back to link"      bash -c "test -d '$HOME/.codex/skills/land' && ! test -L '$HOME/.codex/skills/land'"

# --- 9a. unowned FOREIGN SYMLINK is preserved without --adopt (Codex P2 #1) ---
mkdir -p "$HOME/.claude/skills" "$SB/user-own-skill"
echo custom > "$SB/user-own-skill/SKILL.md"
"$SRC/install.sh" >/dev/null 2>&1   # reinstall after uninstall in test 8
rm -rf "$HOME/.claude/skills/triage"
ln -s "$SB/user-own-skill" "$HOME/.claude/skills/triage"
grep -v '^triage ' "$HOME/.claude/skills/.borrowedfire-manifest" > "$SB/m2" && mv "$SB/m2" "$HOME/.claude/skills/.borrowedfire-manifest"
OUT="$("$SRC/install.sh" 2>&1)"
check "foreign symlink skipped"        grep -q 'SKIP.*triage' <<<"$OUT"
check "foreign symlink not repointed"  test "$(readlink "$HOME/.claude/skills/triage")" = "$SB/user-own-skill"
check "foreign link not in manifest"   bash -c "! grep -q '^triage ' '$HOME/.claude/skills/.borrowedfire-manifest'"
"$SRC/install.sh" --adopt >/dev/null 2>&1
check "adopt replaces foreign symlink" test "$(readlink "$HOME/.claude/skills/triage")" = "$SRC/skills/triage"

# --- 9b. paths with spaces (Codex P2 #2) ---
SPHOME="$SB/home with spaces"
mkdir -p "$SPHOME/.claude" "$SB/oc ws"
HOME="$SPHOME" "$SRC/install.sh" --openclaw-workspace "$SB/oc ws" >/dev/null 2>&1
check "spaces: claude skill linked"    test -L "$SPHOME/.claude/skills/remember"
check "spaces: doctrine written"       grep -q 'BEGIN BORROWEDFIRE DOCTRINE' "$SPHOME/.claude/CLAUDE.md"
check "spaces: openclaw ws linked"     test -L "$SB/oc ws/skills/land"
check "spaces: no stray dirs created"  bash -c "! test -e ./with && ! test -e ./spaces && ! test -e ./ws && ! test -e '$SB/oc'"

# --- 9c. removal shape-guard (Codex P1): user-replaced entries survive uninstall/prune ---
rm -rf "$HOME/.qwen/skills"   # reset out of sticky copy mode from test 6
mkdir -p "$HOME/.qwen/skills"
"$SRC/install.sh" >/dev/null 2>&1
# manifest says link, but user replaced the symlink with their own real dir
rm -rf "$HOME/.qwen/skills/ship"
mkdir -p "$HOME/.qwen/skills/ship"; echo precious > "$HOME/.qwen/skills/ship/SKILL.md"
# manifest says link, but user repointed the symlink elsewhere
rm -rf "$HOME/.qwen/skills/deps"
ln -s "$SB/user-own-skill" "$HOME/.qwen/skills/deps"
OUT="$("$SRC/install.sh" --uninstall 2>&1)"
check "guard: replaced dir survives"   grep -q precious "$HOME/.qwen/skills/ship/SKILL.md"
check "guard: foreign link survives"   test "$(readlink "$HOME/.qwen/skills/deps")" = "$SB/user-own-skill"
check "guard: ours still removed"      test ! -e "$HOME/.qwen/skills/land"
check "guard: LEAVE reported"          grep -q 'LEAVE.*ship' <<<"$OUT"

# --- 9d. copy-marker guard (Codex P2): user dir at a copy-owned name survives ---
rm -rf "$HOME/.qwen/skills"; mkdir -p "$HOME/.qwen/skills"
"$SRC/install.sh" --copy >/dev/null 2>&1
check "marker present in copies"       test -e "$HOME/.qwen/skills/ship/.borrowedfire-copy"
rm -rf "$HOME/.qwen/skills/ship"
mkdir -p "$HOME/.qwen/skills/ship"; echo precious2 > "$HOME/.qwen/skills/ship/SKILL.md"
OUT="$("$SRC/install.sh" --uninstall 2>&1)"
check "copy-guard: user dir survives"  grep -q precious2 "$HOME/.qwen/skills/ship/SKILL.md"
check "copy-guard: our copies removed" test ! -e "$HOME/.qwen/skills/land"
check "copy-guard: LEAVE reported"     grep -q 'LEAVE.*ship' <<<"$OUT"

# --- 9e. moved-checkout uninstall (Codex P2 round 5): dangling owned links removed ---
rm -rf "$HOME/.qwen/skills"; mkdir -p "$HOME/.qwen/skills"
"$SRC/install.sh" >/dev/null 2>&1
# simulate a moved checkout: owned link now points at a path that no longer exists
rm "$HOME/.qwen/skills/triage"
ln -s "$SB/old-checkout/skills/triage" "$HOME/.qwen/skills/triage"
# and a working foreign link at another owned name (user replacement) must survive
rm "$HOME/.qwen/skills/signal"
ln -s "$SB/user-own-skill" "$HOME/.qwen/skills/signal"
OUT="$("$SRC/install.sh" --uninstall 2>&1)"
check "moved: dangling link removed"   test ! -L "$HOME/.qwen/skills/triage"
check "moved: working foreign kept"    test "$(readlink "$HOME/.qwen/skills/signal")" = "$SB/user-own-skill"

# --- 9f. CODEX_HOME honored (Codex P2 round 6) ---
mkdir -p "$SB/codex-custom"
CODEX_HOME="$SB/codex-custom" "$SRC/install.sh" >/dev/null 2>&1
check "CODEX_HOME: skills installed"   test -L "$SB/codex-custom/skills/land"
check "CODEX_HOME: doctrine written"   grep -q 'BEGIN BORROWEDFIRE DOCTRINE' "$SB/codex-custom/AGENTS.md"

# --- 9g. pre-existing correct symlink gets recorded (Codex P2 round 6) ---
rm -rf "$HOME/.claude/skills"; mkdir -p "$HOME/.claude/skills"
ln -s "$SRC/skills/recall" "$HOME/.claude/skills/recall"   # manual pre-installer link, no manifest
"$SRC/install.sh" >/dev/null 2>&1
check "adopted-link: in manifest"      grep -q '^recall link$' "$HOME/.claude/skills/.borrowedfire-manifest"
"$SRC/install.sh" --uninstall >/dev/null 2>&1
check "adopted-link: uninstallable"    test ! -L "$HOME/.claude/skills/recall"

# --- 10. negative lint test: broken skill fails lint + blocks install ---
CLONE="$SB/clone"
cp -R "$SRC" "$CLONE"
sed -i 's/^name: ship$/name: shipp/' "$CLONE/skills/ship/SKILL.md"
if "$CLONE/tools/skill-lint.sh" >/dev/null 2>&1; then fail "lint catches bad name"; else ok "lint catches bad name"; fi
if "$CLONE/install.sh" >/dev/null 2>&1; then fail "install blocked by lint"; else ok "install blocked by lint"; fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
