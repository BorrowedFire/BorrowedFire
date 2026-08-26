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
STALE_NAMES="takeoff autoland orbit repo-quality-audit blackbox debrief reentry resupply flightplan postcard launchpad afterglow ember rekindle tend hearth borrowedfire-learn"

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
for m in remember recall digest reflect; do
  [ -d "$SKILLS_DIR/$m" ] || err "memory system incomplete: missing '$m'"
done
[ -f "$SKILLS_DIR/remember/references/brain-schema.md" ] || err "missing remember/references/brain-schema.md (recall + digest depend on it)"

LEARN_SKILL="$SKILLS_DIR/reflect/SKILL.md"
DOCTRINE="$ROOT/doctrine/DOCTRINE.md"
SAFE_DOCTRINE="$ROOT/doctrine/DOCTRINE_NO_LEARNING.md"
if ! body "$LEARN_SKILL" | grep -qF 'Run without a user prompt'; then
  err "reflect: automatic checkpoint invocation is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'No autonomous self-rewrite'; then
  err "reflect: self-modification boundary is missing"
fi
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
if ! grep -qF 'run `reflect` automatically' "$DOCTRINE"; then
  err "doctrine: automatic learning checkpoint is missing"
fi
# shellcheck disable=SC2016  # backticks are intentional literal contract text
if grep -qF 'run `reflect` automatically' "$SAFE_DOCTRINE"; then
  err "safe doctrine: automatic learning checkpoint must be disabled"
fi
# shellcheck disable=SC2016  # backticks are intentional literal contract text
if ! grep -qF '**Safety.** The `land` denylist is always owner-gated' "$SAFE_DOCTRINE" ||
   ! grep -qF '**Memory.** Prometheus is the private git-backed brain.' "$SAFE_DOCTRINE"; then
  err "safe doctrine: non-learning memory and safety contracts are missing"
fi

# writing contract: both doctrine variants carry the always-on prose rule and its routing.
# Without this, an edit can silently drop the mandate and every harness stops applying it.
# Matched against a whitespace-flattened copy on purpose: these sentences are hard-wrapped for
# reading, and re-wrapping a paragraph must not silently drop a contract. A line-anchored
# `grep -F` on prose breaks the first time a word moves across the wrap.
doctrine_has() { # doctrine_has <file> <literal phrase>
  tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF "$2"
}
# The writing RULES are self-contained prose and must survive degradation, so both variants carry
# them. The skill MANDATES must not appear in the reduced doctrine: the installer falls back to it
# precisely when it could not verify those skills, and mandating an unverified skill is the defect
# this contract exists to prevent.
for doctrine_file in "$DOCTRINE" "$SAFE_DOCTRINE"; do
  doctrine_name="$(basename "$doctrine_file")"
  doctrine_has "$doctrine_file" '**Writing.**' || err "$doctrine_name: the always-on writing contract is missing"
done
# shellcheck disable=SC2016  # backticks are intentional literal contract text
doctrine_has "$DOCTRINE" 'Run `unslop` on prose before it ships' || err "doctrine: unslop is not mandated before prose ships"
# shellcheck disable=SC2016  # backticks are intentional literal contract text
doctrine_has "$DOCTRINE" 'Use `technical-writing` for docs' || err "doctrine: technical-writing routing is missing"
# shellcheck disable=SC2016  # backticks are intentional literal contract text
if doctrine_has "$SAFE_DOCTRINE" 'Run `unslop` on prose before it ships' || doctrine_has "$SAFE_DOCTRINE" 'Use `technical-writing` for docs'; then
  err "reduced doctrine: writing skills must not be mandated when the installer could not verify them"
fi

# The installer must verify every skill the full doctrine mandates by name.
for mandated in unslop technical-writing; do
  grep -q "^WRITING_SKILLS=.*$mandated" "$ROOT/install.sh" ||
    err "install.sh: WRITING_SKILLS omits '$mandated', so the doctrine would mandate an unverified skill"
done
# shellcheck disable=SC2016  # the literal \$VAR text in install.sh is the thing being matched
grep -q '^DOCTRINE_SKILLS="\$LEARNING_SKILLS \$WRITING_SKILLS"' "$ROOT/install.sh" ||
  err "install.sh: DOCTRINE_SKILLS must be the union of LEARNING_SKILLS and WRITING_SKILLS"

# The cycle installer repeats the learning stack in two Python literals, and it gates the scheduler
# declaration on them. A rename that updates only install.sh leaves that gate checking stale names,
# which is exactly how a stored controller ends up naming a skill that no longer exists.
CYCLE_INSTALLER="$ROOT/tools/install-prometheus-cycle.sh"
if [ -f "$CYCLE_INSTALLER" ]; then
  mandated_list="$(sed -n 's/^LEARNING_SKILLS="\(.*\)"$/\1/p' "$ROOT/install.sh") $(sed -n 's/^WRITING_SKILLS="\(.*\)"$/\1/p' "$ROOT/install.sh")"
  for mandated_skill in $mandated_list; do
    grep -q "^skills = (.*\"$mandated_skill\"" "$CYCLE_INSTALLER" ||
      err "install-prometheus-cycle.sh: 'skills' integrity check omits '$mandated_skill'; the nightly job would activate a doctrine mandating an unverified skill"
    grep -q "^required = {.*\"$mandated_skill\"" "$CYCLE_INSTALLER" ||
      err "install-prometheus-cycle.sh: 'required' visibility gate omits '$mandated_skill'; the nightly job would activate a doctrine mandating an unverified skill"
  done
fi
if ! body "$SKILLS_DIR/technical-writing/SKILL.md" | grep -qF 'ASD-STE100'; then
  err "technical-writing: the ASD-STE100 instruction layer is missing"
fi
if ! body "$SKILLS_DIR/unslop/SKILL.md" | grep -qF 'Established domain terms win'; then
  err "unslop: the established-domain-terms carve-out is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'notes/openclaw-<host>-<agent>-<workspace>-<binding-hash>-ingest.md'; then
  err "reflect: host-scoped watermark contract is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'effective OpenClaw' ||
   ! body "$LEARN_SKILL" | grep -qF 'do not backfill pre-existing session notes'; then
  err "reflect: controller identity and prospective bootstrap contracts are missing"
fi
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
if ! body "$LEARN_SKILL" | grep -qF 'exact local-only `.brain-outbox/<file>`'; then
  err "reflect: narrow outbox cleanup contract is missing"
fi
if ! body "$LEARN_SKILL" | grep -qF 'keep the pending capture in output only'; then
  err "reflect: unavailable-brain fallback must remain output-only without repo-write authority"
fi
if ! body "$LEARN_SKILL" | grep -qF 'fleet mode never creates a fallback outbox in a product repository'; then
  err "reflect: fleet mode must not write a product-repo fallback outbox"
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

# proof-ladder contracts, matched wrap-proof (a re-wrap must not silently drop a contract):
if ! body "$LAND_SKILL" | tr '\n' ' ' | tr -s ' ' | grep -qF 'every recorded proof names the rung'; then
  err "land: the proof-ladder rung requirement is missing"
fi
if ! body "$LAND_SKILL" | tr '\n' ' ' | tr -s ' ' | grep -qF 'passes this gate at rung 4 or higher'; then
  err "land: the rung-4 passing threshold is missing"
fi
if ! body "$LAND_SKILL" | tr '\n' ' ' | tr -s ' ' | grep -qF 'passed at the rung floor for its class'; then
  err "land: the merge predicate must require the class rung floor, not a mere record"
fi
if ! body "$QA_AUDIT_SKILL" | tr '\n' ' ' | tr -s ' ' | grep -qF 'means rung 4 or higher'; then
  err "qa-audit: the rung-4 proven threshold is missing"
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
