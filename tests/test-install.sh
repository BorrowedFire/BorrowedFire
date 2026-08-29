#!/usr/bin/env bash
# Sandbox verification for install.sh. Runs against a fake HOME.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
# Derived, never hardcoded: a literal count goes stale the next time a skill is added.
SKILL_COUNT="$(find "$SRC/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d " ")"
SB="$(mktemp -d)"
export HOME="$SB/home"
export XDG_CONFIG_HOME="$HOME/.config"   # hermetic: the runner's config root must not leak in
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
check "claude: closeout linked"        test -L "$HOME/.claude/skills/session-closeout"
check "codex: closeout linked"         test -L "$HOME/.codex/skills/session-closeout"
check "qwen: maintainer linked"        test -L "$HOME/.qwen/skills/maintainer"
check "openclaw: digest linked"        test -L "$SB/openclaw-ws/skills/digest"
check "claude: learning linked"        test -L "$HOME/.claude/skills/reflect"
check "codex: learning linked"         test -L "$HOME/.codex/skills/reflect"
check "openclaw: learning linked"      test -L "$SB/openclaw-ws/skills/reflect"
check "claude: manifest written"       grep -q '^remember link$' "$HOME/.claude/skills/.borrowedfire-manifest"
check "claude: doctrine block present" grep -q 'BEGIN BORROWEDFIRE DOCTRINE' "$HOME/.claude/CLAUDE.md"
check "openclaw: doctrine in AGENTS.md" grep -q 'BEGIN BORROWEDFIRE DOCTRINE' "$SB/openclaw-ws/AGENTS.md"
check "manifest has every skill"       test "$(wc -l < "$HOME/.claude/skills/.borrowedfire-manifest")" -eq "$SKILL_COUNT"

# --- 2. idempotence: re-run, doctrine is byte-identical and appears exactly once ---
cp "$HOME/.claude/CLAUDE.md" "$SB/claude-doctrine-before"
"$SRC/install.sh" --openclaw-workspace "$SB/openclaw-ws" >/dev/null 2>&1
check "doctrine idempotent (byte-identical)" cmp -s "$SB/claude-doctrine-before" "$HOME/.claude/CLAUDE.md"
check "doctrine idempotent (1 block)"  test "$(grep -c 'BEGIN BORROWEDFIRE DOCTRINE' "$HOME/.claude/CLAUDE.md")" -eq 1
check "manifest unchanged on re-run"   test "$(wc -l < "$HOME/.claude/skills/.borrowedfire-manifest")" -eq "$SKILL_COUNT"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "doctrine invokes namespaced learning" grep -q 'run `reflect` automatically' "$HOME/.claude/CLAUDE.md"

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
mkdir -p "$HOME/prometheus/config" "$HOME/prometheus/projects"
git init -q "$HOME/prometheus"
printf '%s\n' 'journal/*.md merge=union' 'inbox/*.md merge=union' \
  'projects/*.md merge=union' > "$HOME/prometheus/.gitattributes"
touch "$HOME/prometheus/INDEX.md" "$HOME/prometheus/config/fleet.md"
"$SRC/install.sh" >/dev/null 2>&1
check "schema-valid brain without helper template is accepted" \
  grep -q "$HOME/prometheus" "$HOME/.config/borrowedfire/brain"
check "explicit brain pointer is owner-private" \
  test "$(stat -c '%a' "$HOME/.config/borrowedfire/brain" 2>/dev/null || stat -f '%Lp' "$HOME/.config/borrowedfire/brain" 2>/dev/null)" = 600

INVALID_BRAIN_HOME="$SB/invalid-explicit-brain-home"
mkdir -p "$INVALID_BRAIN_HOME/.codex" "$INVALID_BRAIN_HOME/.config/borrowedfire"
printf '%s\n' "$HOME/prometheus" > "$INVALID_BRAIN_HOME/.config/borrowedfire/brain"
if HOME="$INVALID_BRAIN_HOME" "$SRC/install.sh" --brain "$SB/not-a-brain" >/dev/null 2>&1; then
  fail "invalid explicit brain fails before install"
else
  ok "invalid explicit brain fails before install"
fi
check "invalid explicit brain leaves prior pointer intact" \
  grep -qxF "$HOME/prometheus" "$INVALID_BRAIN_HOME/.config/borrowedfire/brain"
check "invalid explicit brain installs no skills" test ! -e "$INVALID_BRAIN_HOME/.codex/skills"
check "invalid explicit brain installs no doctrine" test ! -e "$INVALID_BRAIN_HOME/.codex/AGENTS.md"

PARTIAL_HOME="$SB/partial-install-home"
mkdir -p "$PARTIAL_HOME/.codex/skills/reflect" "$PARTIAL_HOME/.config/borrowedfire"
echo foreign > "$PARTIAL_HOME/.codex/skills/reflect/SKILL.md"
printf '%s\n' "$SB/old-brain" > "$PARTIAL_HOME/.config/borrowedfire/brain"
CANONICAL_TEST_BRAIN="$(cd "$HOME/prometheus" && pwd -P)"
if HOME="$PARTIAL_HOME" "$SRC/install.sh" --brain "$CANONICAL_TEST_BRAIN" >/dev/null 2>&1; then
  fail "partial harness failure remains nonzero after brain switch"
else
  ok "partial harness failure remains nonzero after brain switch"
fi
check "valid requested brain is bound before partial harness failure" \
  grep -qxF "$CANONICAL_TEST_BRAIN" "$PARTIAL_HOME/.config/borrowedfire/brain"
check "partial harness failure never retains stale automatic doctrine" bash -c \
  "! grep -q 'run \`reflect\` automatically' '$PARTIAL_HOME/.codex/AGENTS.md'"

NESTED_HOME="$SB/nested-brain-home"
mkdir -p "$NESTED_HOME/.codex" "$NESTED_HOME/prometheus/config" "$NESTED_HOME/prometheus/projects"
git init -q "$NESTED_HOME"
printf '%s\n' 'journal/*.md merge=union' 'inbox/*.md merge=union' \
  'projects/*.md merge=union' > "$NESTED_HOME/prometheus/.gitattributes"
touch "$NESTED_HOME/prometheus/INDEX.md" "$NESTED_HOME/prometheus/config/fleet.md" \
  "$NESTED_HOME/prometheus/projects/_template.md"
HOME="$NESTED_HOME" "$SRC/install.sh" >/dev/null 2>&1
check "nested automatic brain root is rejected" test ! -e "$NESTED_HOME/.config/borrowedfire/brain"

# --- 7b. an unmanaged automatic-learning collision fails closed before doctrine install ---
COLLISION_HOME="$SB/collision-home"
mkdir -p "$COLLISION_HOME/.codex/skills/reflect"
echo foreign > "$COLLISION_HOME/.codex/skills/reflect/SKILL.md"
if HOME="$COLLISION_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
  fail "unmanaged learning collision fails closed"
else
  ok "unmanaged learning collision fails closed"
fi
check "foreign learning skill remains intact" grep -q foreign "$COLLISION_HOME/.codex/skills/reflect/SKILL.md"
check "collision harness gets no learning doctrine" bash -c "! grep -q 'run \`reflect\` automatically' '$COLLISION_HOME/.codex/AGENTS.md'"
check "collision harness retains safety doctrine" grep -q '^\*\*Safety\.\*\*' "$COLLISION_HOME/.codex/AGENTS.md"
check "collision harness retains memory doctrine" grep -q '^\*\*Memory\.\*\*' "$COLLISION_HOME/.codex/AGENTS.md"

# --- 7c. an unmanaged WRITING collision fails closed the same way ---
# The doctrine mandates unslop and technical-writing by name, so an unverified copy of either must
# never be activated. The reduced doctrine keeps the writing RULES (self-contained prose) and drops
# only the skill mandates.
WRITING_COLLISION_HOME="$SB/writing-collision-home"
mkdir -p "$WRITING_COLLISION_HOME/.codex/skills/unslop"
echo foreign > "$WRITING_COLLISION_HOME/.codex/skills/unslop/SKILL.md"
if HOME="$WRITING_COLLISION_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
  fail "unmanaged writing collision fails closed"
else
  ok "unmanaged writing collision fails closed"
fi
check "foreign writing skill remains intact" \
  grep -q foreign "$WRITING_COLLISION_HOME/.codex/skills/unslop/SKILL.md"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "writing collision harness does not mandate unslop" bash -c \
  "! grep -q '\`unslop\` on prose before it ships' '$WRITING_COLLISION_HOME/.codex/AGENTS.md'"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "writing collision harness does not mandate technical-writing" bash -c \
  "! grep -q 'Use \`technical-writing\` for docs' '$WRITING_COLLISION_HOME/.codex/AGENTS.md'"
check "writing collision harness keeps the writing rules" \
  grep -q '^\*\*Writing\.\*\*' "$WRITING_COLLISION_HOME/.codex/AGENTS.md"
check "writing collision harness retains safety doctrine" \
  grep -q '^\*\*Safety\.\*\*' "$WRITING_COLLISION_HOME/.codex/AGENTS.md"
check "writing collision harness reports reduced mode" \
  grep -q '^\*\*Reduced mode\.\*\*' "$WRITING_COLLISION_HOME/.codex/AGENTS.md"

STALE_HOME="$SB/stale-owned-home"
mkdir -p "$STALE_HOME/.codex/skills/reflect"
echo foreign > "$STALE_HOME/.codex/skills/reflect/SKILL.md"
echo 'reflect link' > "$STALE_HOME/.codex/skills/.borrowedfire-manifest"
if HOME="$STALE_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
  fail "stale ownership shape fails closed"
else
  ok "stale ownership shape fails closed"
fi
check "stale ownership does not install doctrine" bash -c "! grep -q 'run \`reflect\` automatically' '$STALE_HOME/.codex/AGENTS.md'"
check "stale ownership retains safety doctrine" grep -q '^\*\*Safety\.\*\*' "$STALE_HOME/.codex/AGENTS.md"

REPLACED_HOME="$SB/replaced-owned-home"
mkdir -p "$REPLACED_HOME/.codex"
HOME="$REPLACED_HOME" "$SRC/install.sh" >/dev/null 2>&1
unlink "$REPLACED_HOME/.codex/skills/reflect"
mkdir "$REPLACED_HOME/.codex/skills/reflect"
echo foreign > "$REPLACED_HOME/.codex/skills/reflect/SKILL.md"
if HOME="$REPLACED_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
  fail "replaced managed learning skill fails closed"
else
  ok "replaced managed learning skill fails closed"
fi
check "stale automatic learning trigger is removed" bash -c "! grep -q 'run \`reflect\` automatically' '$REPLACED_HOME/.codex/AGENTS.md'"
check "replaced learning skill retains safety doctrine" grep -q '^\*\*Safety\.\*\*' "$REPLACED_HOME/.codex/AGENTS.md"
if HOME="$REPLACED_HOME" "$SRC/install.sh" --dry-run >/dev/null 2>&1; then
  fail "collision dry-run reports failure"
else
  ok "collision dry-run reports failure"
fi

READ_ONLY_HOME="$SB/read-only-context-home"
mkdir -p "$READ_ONLY_HOME/.codex"
HOME="$READ_ONLY_HOME" "$SRC/install.sh" >/dev/null 2>&1
unlink "$READ_ONLY_HOME/.codex/skills/reflect"
mkdir "$READ_ONLY_HOME/.codex/skills/reflect"
echo foreign > "$READ_ONLY_HOME/.codex/skills/reflect/SKILL.md"
chmod 444 "$READ_ONLY_HOME/.codex/AGENTS.md"
if HOME="$READ_ONLY_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
  fail "read-only stale doctrine collision fails closed"
else
  ok "read-only stale doctrine collision fails closed"
fi
check "read-only context gets atomic safe doctrine replacement" \
  grep -q 'Automatic learning is disabled' "$READ_ONLY_HOME/.codex/AGENTS.md"
check "read-only context no longer invokes automatic learning" bash -c \
  "! grep -q 'run \`reflect\` automatically' '$READ_ONLY_HOME/.codex/AGENTS.md'"

SYMLINK_HOME="$SB/symlink-context-home"
mkdir -p "$SYMLINK_HOME/.codex" "$SYMLINK_HOME/shared"
printf '%s\n' 'shared owner context' > "$SYMLINK_HOME/shared/AGENTS.md"
ln -s ../shared/AGENTS.md "$SYMLINK_HOME/.codex/AGENTS.md"
HOME="$SYMLINK_HOME" "$SRC/install.sh" >/dev/null 2>&1
check "symlinked context remains a symlink" test -L "$SYMLINK_HOME/.codex/AGENTS.md"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "symlinked context target receives doctrine" \
  grep -q 'run `reflect` automatically' "$SYMLINK_HOME/shared/AGENTS.md"
HOME="$SYMLINK_HOME" "$SRC/install.sh" --uninstall >/dev/null 2>&1
check "symlinked context survives uninstall" test -L "$SYMLINK_HOME/.codex/AGENTS.md"
check "symlinked context target retains owner content" \
  grep -q '^shared owner context$' "$SYMLINK_HOME/shared/AGENTS.md"
check "symlinked context target loses doctrine on uninstall" bash -c \
  "! grep -q 'BORROWEDFIRE DOCTRINE' '$SYMLINK_HOME/shared/AGENTS.md'"

STALE_COPY_HOME="$SB/stale-copy-home"
STALE_COPY_SOURCE="$SB/stale-copy-source"
mkdir -p "$STALE_COPY_HOME/.codex"
HOME="$STALE_COPY_HOME" "$SRC/install.sh" --copy >/dev/null 2>&1
cp -R "$SRC" "$STALE_COPY_SOURCE"
printf '%s\n' '<!-- copied-learning-contract-v2 -->' >> \
  "$STALE_COPY_SOURCE/skills/reflect/SKILL.md"
mkdir -p "$SB/failing-copy-bin"
# shellcheck disable=SC2016  # write a fixture that expands its own argv
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "-rf" ]; then exit 77; fi' \
  'exec /bin/rm "$@"' > "$SB/failing-copy-bin/rm"
chmod +x "$SB/failing-copy-bin/rm"
if HOME="$STALE_COPY_HOME" PATH="$SB/failing-copy-bin:$PATH" \
  "$STALE_COPY_SOURCE/install.sh" --copy >/dev/null 2>&1; then
  fail "stale copied learning dependency fails closed"
else
  ok "stale copied learning dependency fails closed"
fi
check "failed copy refresh leaves prior skill intact" bash -c \
  "! grep -q 'copied-learning-contract-v2' '$STALE_COPY_HOME/.codex/skills/reflect/SKILL.md'"
check "stale copied learning dependency disables automatic doctrine" bash -c \
  "! grep -q 'run \`reflect\` automatically' '$STALE_COPY_HOME/.codex/AGENTS.md'"
check "stale copied learning dependency retains safety doctrine" \
  grep -q '^\*\*Safety\.\*\*' "$STALE_COPY_HOME/.codex/AGENTS.md"

UNINSTALL_FAILURE_HOME="$SB/uninstall-failure-home"
mkdir -p "$UNINSTALL_FAILURE_HOME/.codex"
HOME="$UNINSTALL_FAILURE_HOME" "$SRC/install.sh" >/dev/null 2>&1
mkdir -p "$SB/failing-doctrine-bin"
# shellcheck disable=SC2016  # write a fixture that expands its own argv
printf '%s\n' '#!/usr/bin/env bash' \
  'case "${1:-}" in */.borrowedfire-doctrine.XXXXXX) exit 77 ;; esac' \
  'exec /usr/bin/mktemp "$@"' > "$SB/failing-doctrine-bin/mktemp"
chmod +x "$SB/failing-doctrine-bin/mktemp"
if HOME="$UNINSTALL_FAILURE_HOME" PATH="$SB/failing-doctrine-bin:$PATH" \
  "$SRC/install.sh" --uninstall >/dev/null 2>&1; then
  fail "failed doctrine rewrite fails uninstall"
else
  ok "failed doctrine rewrite fails uninstall"
fi
check "failed doctrine removal leaves learning skill installed" \
  test -e "$UNINSTALL_FAILURE_HOME/.codex/skills/reflect"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "failed doctrine removal leaves matching automatic doctrine" \
  grep -q 'run `reflect` automatically' "$UNINSTALL_FAILURE_HOME/.codex/AGENTS.md"

for dependency in remember recall digest; do
  DEPENDENCY_HOME="$SB/foreign-$dependency-home"
  mkdir -p "$DEPENDENCY_HOME/.codex/skills/$dependency"
  echo foreign > "$DEPENDENCY_HOME/.codex/skills/$dependency/SKILL.md"
  if HOME="$DEPENDENCY_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
    fail "unmanaged $dependency dependency fails closed"
  else
    ok "unmanaged $dependency dependency fails closed"
  fi
  check "unmanaged $dependency suppresses doctrine" bash -c \
    "! grep -q 'run \`reflect\` automatically' '$DEPENDENCY_HOME/.codex/AGENTS.md'"
  check "unmanaged $dependency retains safety doctrine" grep -q '^\*\*Safety\.\*\*' \
    "$DEPENDENCY_HOME/.codex/AGENTS.md"
done

MOVED_HOME="$SB/moved-learning-home"
mkdir -p "$MOVED_HOME/.codex"
HOME="$MOVED_HOME" "$SRC/install.sh" >/dev/null 2>&1
for dependency in reflect remember recall digest; do
  unlink "$MOVED_HOME/.codex/skills/$dependency"
  ln -s "$SB/old-borrowedfire/skills/$dependency" "$MOVED_HOME/.codex/skills/$dependency"
done
if HOME="$MOVED_HOME" "$SRC/install.sh" >/dev/null 2>&1; then
  ok "moved-checkout learning links are repointed"
else
  fail "moved-checkout learning links are repointed"
fi
check "repointed learning link uses current checkout" \
  test "$(readlink "$MOVED_HOME/.codex/skills/reflect")" = "$SRC/skills/reflect"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "repointed stack retains automatic doctrine" \
  grep -q 'run `reflect` automatically' "$MOVED_HOME/.codex/AGENTS.md"

MOVED_COPY_HOME="$SB/moved-copy-home"
mkdir -p "$MOVED_COPY_HOME/.codex"
HOME="$MOVED_COPY_HOME" "$SRC/install.sh" >/dev/null 2>&1
unlink "$MOVED_COPY_HOME/.codex/skills/remember"
ln -s "$SB/old-borrowedfire/skills/remember" "$MOVED_COPY_HOME/.codex/skills/remember"
if HOME="$MOVED_COPY_HOME" "$SRC/install.sh" --copy >/dev/null 2>&1; then
  ok "copy mode converges after a managed checkout moves"
else
  fail "copy mode converges after a managed checkout moves"
fi
check "copy mode converts a moved managed link" bash -c \
  "test -d '$MOVED_COPY_HOME/.codex/skills/remember' && ! test -L '$MOVED_COPY_HOME/.codex/skills/remember'"
check "moved-link conversion records copy ownership" \
  grep -q '^remember copy$' "$MOVED_COPY_HOME/.codex/skills/.borrowedfire-manifest"
check "moved-link conversion installs the exact current skill" \
  diff -qr -x .borrowedfire-copy "$SRC/skills/remember" "$MOVED_COPY_HOME/.codex/skills/remember"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "moved-link conversion retains automatic doctrine" \
  grep -q 'run `reflect` automatically' "$MOVED_COPY_HOME/.codex/AGENTS.md"

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
if "$SRC/install.sh" >/dev/null 2>&1; then
  ok "adopted-link: automatic stack remains valid"
else
  fail "adopted-link: automatic stack remains valid"
fi
check "adopted-link: in manifest"      grep -q '^recall link$' "$HOME/.claude/skills/.borrowedfire-manifest"
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
check "adopted-link: doctrine retained" grep -q 'run `reflect` automatically' "$HOME/.claude/CLAUDE.md"
"$SRC/install.sh" --uninstall >/dev/null 2>&1
check "adopted-link: uninstallable"    test ! -L "$HOME/.claude/skills/recall"

# --- 10. negative lint test: broken skill fails lint + blocks install ---
CLONE="$SB/clone"
cp -R "$SRC" "$CLONE"
sed -i.bak 's/^name: ship$/name: shipp/' "$CLONE/skills/ship/SKILL.md"
rm -f "$CLONE/skills/ship/SKILL.md.bak"
if "$CLONE/tools/skill-lint.sh" >/dev/null 2>&1; then fail "lint catches bad name"; else ok "lint catches bad name"; fi
if "$CLONE/install.sh" >/dev/null 2>&1; then fail "install blocked by lint"; else ok "install blocked by lint"; fi

# --- 11. workflow-contract regressions fail closed ---
contract_lint_case() {
  label="$1"
  relative_file="$2"
  edit_expression="$3"
  contract_clone="$SB/contract-$label"
  cp -R "$SRC" "$contract_clone"
  sed -i.bak "$edit_expression" "$contract_clone/$relative_file"
  rm -f "$contract_clone/$relative_file.bak"
  if "$contract_clone/tools/skill-lint.sh" >/dev/null 2>&1; then
    fail "contract lint: $label"
  else
    ok "contract lint: $label"
  fi
}

contract_lint_case "post-audit-validation" "skills/land/SKILL.md" \
  's/new validated related finding surfaces/new related finding surfaces/'
contract_lint_case "release-branch-eligibility" "skills/land/SKILL.md" \
  's/Only findings \*\*eligible for in-loop fixing\*\*/Only validated findings/'
contract_lint_case "artifact-root-routing" "skills/qa-audit/SKILL.md" \
  's#<audit-dir>/test-matrix.md#qa/test-matrix.md#'
contract_lint_case "no-fix-precedence" "skills/qa-audit/SKILL.md" \
  "s/\`--no-fix\` overrides \`--fix-safe\`/\`--no-fix\` and \`--fix-safe\`/"
contract_lint_case "audit-only-mode" "skills/qa-audit/SKILL.md" \
  "s/When \`--no-fix\`/When audit-only mode/"
contract_lint_case "writing-doctrine" "doctrine/DOCTRINE.md" \
  's/\*\*Writing\.\*\*/**Prose.**/'
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
contract_lint_case "writing-doctrine-mandate" "doctrine/DOCTRINE.md" \
  's/`unslop` on prose before it ships/unslop sometimes/'
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
contract_lint_case "reduced-doctrine-mandates-nothing-unverified" "doctrine/DOCTRINE_NO_LEARNING.md" \
  's/The$/Run `unslop` on prose before it ships. The/'
contract_lint_case "installer-verifies-writing-skills" "install.sh" \
  's/^WRITING_SKILLS=.*/WRITING_SKILLS="unslop"/'
contract_lint_case "cycle-installer-skill-drift" "tools/install-prometheus-cycle.sh" \
  's/^required = {"reflect", /required = {"stale-name", /'
contract_lint_case "land-proof-ladder" "skills/land/SKILL.md" \
  's/every recorded proof names the rung/a proof may name the rung/'
contract_lint_case "land-rung-threshold" "skills/land/SKILL.md" \
  's/passes this gate at rung 4 or higher/passes this gate at any rung/'
# the predicate phrase hard-wraps; mutate the sub-phrase that sits on one line
contract_lint_case "land-merge-rung-floor" "skills/land/SKILL.md" \
  's/rung floor for its class/record/'
contract_lint_case "qa-audit-proven-threshold" "skills/qa-audit/SKILL.md" \
  's/means rung 4 or higher/means any recorded evidence/'

# --- 12. inventory-agreement contracts fail closed ---
contract_lint_case "routing-covers-every-skill" "doctrine/DOCTRINE.md" \
  '/reel-maker/d'
contract_lint_case "reduced-routing-covers-every-skill" "doctrine/DOCTRINE_NO_LEARNING.md" \
  '/reel-maker/d'
contract_lint_case "readme-links-every-skill" "README.md" \
  '\#skills/reel-maker/SKILL.md#d'
contract_lint_case "readme-count-matches-tree" "README.md" \
  's/[0-9][0-9]* SKILL\.md skills/999 SKILL.md skills/'
contract_lint_case "readme-count-line-present" "README.md" \
  '/SKILL\.md skills/d'

# a skill added without a routing row or README entry is the drift this contract exists to catch
drift_clone="$SB/contract-new-skill-unrouted"
cp -R "$SRC" "$drift_clone"
mkdir -p "$drift_clone/skills/newskill/agents"
printf '%s\n' '---' 'name: newskill' \
  'description: fixture skill for the inventory-agreement lint.' '---' '' '# Newskill' \
  > "$drift_clone/skills/newskill/SKILL.md"
cp "$SRC/skills/ship/agents/openai.yaml" "$drift_clone/skills/newskill/agents/openai.yaml"
if "$drift_clone/tools/skill-lint.sh" >/dev/null 2>&1; then
  fail "contract lint: new skill without routing/README entries"
else
  ok "contract lint: new skill without routing/README entries"
fi

# --- 13. uninstall names the controller removal step when a controller trace exists ---
"$SRC/install.sh" >/dev/null 2>&1
mkdir -p "$XDG_CONFIG_HOME/borrowedfire"
touch "$XDG_CONFIG_HOME/borrowedfire/prometheus-learning-route.sha256"
OUT="$("$SRC/install.sh" --uninstall 2>&1)"
check "uninstall names install-prometheus-cycle.sh --remove" \
  grep -q 'install-prometheus-cycle.sh --remove' <<<"$OUT"
rm -f "$XDG_CONFIG_HOME/borrowedfire/prometheus-learning-route.sha256"
"$SRC/install.sh" >/dev/null 2>&1
OUT="$("$SRC/install.sh" --uninstall 2>&1)"
if grep -q -- 'install-prometheus-cycle.sh --remove' <<<"$OUT"; then
  fail "uninstall stays quiet with no controller trace"
else
  ok "uninstall stays quiet with no controller trace"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
