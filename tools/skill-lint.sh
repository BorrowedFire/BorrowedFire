#!/usr/bin/env bash
# Lint the Borrowed Fire skill set. Run from anywhere; exits non-zero on any error.
# Also used as install.sh's preflight - never distribute a broken skill set.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$ROOT/skills"
ERRORS=0

err() { echo "ERROR: $*" >&2; ERRORS=$((ERRORS + 1)); }

[ -d "$SKILLS_DIR" ] || { err "no skills/ directory at $ROOT"; exit 1; }

# Names of skills that no longer exist; must not be referenced in any SKILL.md body.
# (Frontmatter descriptions may keep old names as trigger phrases - bodies may not.)
STALE_NAMES="takeoff autoland orbit repo-quality-audit blackbox debrief reentry resupply flightplan postcard launchpad afterglow ember rekindle tend hearth"

# --- collect skill names ---
SKILL_NAMES=""
for dir in "$SKILLS_DIR"/*/; do
  SKILL_NAMES="$SKILL_NAMES $(basename "$dir")"
done

frontmatter() { awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }

for dir in "$SKILLS_DIR"/*/; do
  name="$(basename "$dir")"
  sk="$dir/SKILL.md"

  # 1. SKILL.md exists
  if [ ! -f "$sk" ]; then err "$name: missing SKILL.md"; continue; fi

  # 2. frontmatter name matches directory
  fm_name="$(frontmatter "$sk" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  [ "$fm_name" = "$name" ] || err "$name: frontmatter name '$fm_name' != directory name"

  # 3. description present, single line, <= 1024 chars
  desc="$(frontmatter "$sk" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  if [ -z "$desc" ]; then
    err "$name: missing description"
  elif [ "${#desc}" -gt 1024 ]; then
    err "$name: description is ${#desc} chars (max 1024)"
  fi

  # 4. agents/openai.yaml exists with a policy block
  oy="$dir/agents/openai.yaml"
  if [ ! -f "$oy" ]; then
    err "$name: missing agents/openai.yaml"
  elif ! grep -q '^policy:' "$oy"; then
    err "$name: agents/openai.yaml has no policy: block"
  fi

  # 5. no stale skill names in the body (descriptions may keep them as triggers)
  for stale in $STALE_NAMES; do
    if body "$sk" | grep -qwE "\`?$stale\`?" ; then
      body "$sk" | grep -nwE "\`?$stale\`?" | head -3 | while IFS= read -r line; do
        echo "       $name body: $line" >&2
      done
      err "$name: body references stale skill name '$stale'"
    fi
  done

  # 6. no hardcoded harness skill paths in SKILL.md (references/ may document them)
  # shellcheck disable=SC2088  # literal tilde is the point: we grep for the text
  if body "$sk" | grep -qE '~/\.(claude|codex|qwen)/skills'; then
    err "$name: SKILL.md body hardcodes a harness skills path (move to references/)"
  fi
done

# 7. memory trio installs together
for m in remember recall digest; do
  [ -d "$SKILLS_DIR/$m" ] || err "memory trio incomplete: missing '$m'"
done
[ -f "$SKILLS_DIR/remember/references/brain-schema.md" ] || err "missing remember/references/brain-schema.md (recall + digest depend on it)"

# 8. cross-skill duplicate trigger phrases (quoted strings in descriptions)
TMP="$(mktemp)"
for dir in "$SKILLS_DIR"/*/; do
  name="$(basename "$dir")"
  sk="$dir/SKILL.md"
  [ -f "$sk" ] || continue
  frontmatter "$sk" | sed -n 's/^description:[[:space:]]*//p' | head -1 |
    grep -oE '"[^"]+"' | while IFS= read -r phrase; do
      echo "$phrase $name"
    done
done > "$TMP"
awk '{p=$0; sub(/ [^ ]+$/, "", p); n=$NF; if (seen[p] && seen[p] != n) printf "ERROR: trigger phrase %s claimed by both %s and %s\n", p, seen[p], n; else seen[p]=n}' "$TMP" |
  sort -u | while IFS= read -r line; do echo "$line" >&2; done
DUPES=$(awk '{p=$0; sub(/ [^ ]+$/, "", p); n=$NF; if (seen[p] && seen[p] != n) c++; else seen[p]=n} END{print c+0}' "$TMP")
rm -f "$TMP"
[ "$DUPES" -eq 0 ] || ERRORS=$((ERRORS + DUPES))

if [ "$ERRORS" -gt 0 ]; then
  echo "skill-lint: $ERRORS error(s)" >&2
  exit 1
fi
echo "skill-lint: OK ($(echo "$SKILL_NAMES" | wc -w | tr -d ' ') skills)"
