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

# 7. memory system installs together
for m in remember recall digest borrowedfire-learn; do
  [ -d "$SKILLS_DIR/$m" ] || err "memory system incomplete: missing '$m'"
done
[ -f "$SKILLS_DIR/remember/references/brain-schema.md" ] || err "missing remember/references/brain-schema.md (recall + digest depend on it)"

LEARN_SKILL="$SKILLS_DIR/borrowedfire-learn/SKILL.md"
DOCTRINE="$ROOT/doctrine/DOCTRINE.md"
SAFE_DOCTRINE="$ROOT/doctrine/DOCTRINE_NO_LEARNING.md"
if ! body "$LEARN_SKILL" | grep -qF 'Run without a user prompt'; then
  err "borrowedfire-learn: automatic checkpoint invocation is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'No autonomous self-rewrite'; then
  err "borrowedfire-learn: self-modification boundary is missing"
fi
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
if ! grep -qF 'run `borrowedfire-learn` automatically' "$DOCTRINE"; then
  err "doctrine: automatic learning checkpoint is missing"
fi
# shellcheck disable=SC2016  # backticks are intentional literal contract text
if grep -qF 'run `borrowedfire-learn` automatically' "$SAFE_DOCTRINE"; then
  err "safe doctrine: automatic learning checkpoint must be disabled"
fi
# shellcheck disable=SC2016  # backticks are intentional literal contract text
if ! grep -qF '**Safety.** The `land` denylist is always owner-gated' "$SAFE_DOCTRINE" ||
   ! grep -qF '**Memory.** Prometheus is the private git-backed brain.' "$SAFE_DOCTRINE"; then
  err "safe doctrine: non-learning memory and safety contracts are missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'notes/openclaw-<host>-<agent>-<workspace>-<binding-hash>-ingest.md'; then
  err "borrowedfire-learn: host-scoped watermark contract is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'effective OpenClaw' ||
   ! body "$LEARN_SKILL" | grep -qF 'do not backfill pre-existing session notes'; then
  err "borrowedfire-learn: controller identity and prospective bootstrap contracts are missing"
fi
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
if ! body "$LEARN_SKILL" | grep -qF 'exact local-only `.brain-outbox/<file>`'; then
  err "borrowedfire-learn: narrow outbox cleanup contract is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'keep the pending capture in output only'; then
  err "borrowedfire-learn: unavailable-brain fallback must remain output-only without repo-write authority"
fi
if ! body "$LEARN_SKILL" | grep -qF 'fleet mode never creates a fallback outbox in a product repository'; then
  err "borrowedfire-learn: fleet mode must not write a product-repo fallback outbox"
fi

# 8. workflow contracts that must survive review-loop edits
LAND_SKILL="$SKILLS_DIR/land/SKILL.md"
QA_AUDIT_SKILL="$SKILLS_DIR/qa-audit/SKILL.md"

if ! body "$LAND_SKILL" | grep -qF 'new validated related finding surfaces after the invariant audit and subsequent re-review'; then
  err "land: post-audit escalation must require a new validated related finding"
fi

if ! body "$LAND_SKILL" | grep -qF 'Only findings **eligible for in-loop fixing** under the frozen scope and release-branch rule'; then
  err "land: related-finding audits must preserve release-branch eligibility"
fi

if body "$QA_AUDIT_SKILL" | grep -qE 'qa/(feature-inventory|test-matrix|defects|coverage-summary)\.md'; then
  err "qa-audit: artifact consumers must use <audit-dir>, not a hard-coded qa/ path"
fi

if ! body "$QA_AUDIT_SKILL" | grep -qF "\`--no-fix\` overrides \`--fix-safe\`"; then
  err "qa-audit: --no-fix precedence is missing"
fi

if ! body "$QA_AUDIT_SKILL" | grep -qF "When \`--no-fix\`"; then
  err "qa-audit: invariant circuit breaker must preserve audit-only mode"
fi

# 9. cross-skill duplicate trigger phrases (quoted strings in descriptions)
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
