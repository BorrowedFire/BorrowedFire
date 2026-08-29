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
BRAIN_SCHEMA="$SKILLS_DIR/remember/references/brain-schema.md"
[ -f "$BRAIN_SCHEMA" ] || err "missing remember/references/brain-schema.md (recall + digest depend on it)"

# follow-up ledger contracts: the schema owns the format, digest sweeps it, reflect writes the
# canonical token, brain-lint enforces the INDEX section. Matched wrap-proof where the phrase
# is prose (a re-wrap must not silently drop a contract).
if [ -f "$BRAIN_SCHEMA" ]; then
  grep -q '^## Follow-ups' "$BRAIN_SCHEMA" ||
    err "brain-schema: the §Follow-ups ledger contract is missing"
  grep -qF '## Open follow-ups' "$BRAIN_SCHEMA" ||
    err "brain-schema: the INDEX 'Open follow-ups' section contract is missing"
fi
if ! body "$SKILLS_DIR/digest/SKILL.md" | tr '\n' ' ' | tr -s ' ' | grep -qF 'Normalize follow-ups'; then
  err "digest: the follow-up normalization step is missing"
fi
if ! body "$SKILLS_DIR/digest/SKILL.md" | grep -qF 'no-trigger'; then
  err "digest: the no-trigger rot tag is missing"
fi
# The plural header is the spelling a singular-token sweep misses, and it is how the brain's
# oldest follow-ups are written. A real one went uncollected for six days before this contract.
if ! body "$SKILLS_DIR/digest/SKILL.md" | tr '\n' ' ' | tr -s ' ' | grep -qF 'the plural header "Follow-ups:"'; then
  err "digest: the collection must name the plural Follow-ups: header, which a singular search misses"
fi
if [ -f "$BRAIN_SCHEMA" ] && ! tr '\n' ' ' < "$BRAIN_SCHEMA" | tr -s ' ' | grep -qF 'plural header** "Follow-ups:"'; then
  err "brain-schema: the legacy spelling list must name the plural Follow-ups: header"
fi
# shellcheck disable=SC2016  # backticks are an intentional literal contract phrase
if ! body "$SKILLS_DIR/reflect/SKILL.md" | tr '\n' ' ' | tr -s ' ' | grep -qF 'canonical token `follow-up:`'; then
  err "reflect: the canonical follow-up token rule is missing"
fi
grep -qF 'Open follow-ups' "$ROOT/tools/brain-lint.sh" ||
  err "brain-lint: the INDEX follow-up ledger check is missing"
grep -qF '## Open follow-ups' "$ROOT/prometheus-template/INDEX.md" ||
  err "template INDEX: the 'Open follow-ups' section skeleton is missing"
# The ledger's roles must exist in the skills the schema names. A documented consumer that
# never reads the ledger is the "later means never" rot the section exists to prevent.
for role_skill in recall maintainer land; do
  body "$SKILLS_DIR/$role_skill/SKILL.md" | grep -qF 'Open follow-ups' ||
    body "$SKILLS_DIR/$role_skill/SKILL.md" | grep -qF 'follow-up:' ||
    err "$role_skill: the schema names it in the follow-up lifecycle, but it never reads or writes the ledger"
done
if ! body "$SKILLS_DIR/digest/SKILL.md" | tr '\n' ' ' | tr -s ' ' | grep -qF 'Collect the open set **here**, after steps 8 and 9'; then
  err "digest: the ledger must be collected after distillation and the run's own bullets, or a run hides its own follow-ups"
fi
# Ordering contracts for digest, checked by POSITION rather than by step title or wording.
# A contract pinned to a title survives the retitling and misses the regression: putting the
# reconcile sentence back into the sweep step while leaving its heading alone passed the
# title-based version of this check. A positional test encodes the behavior itself.
DIGEST_BODY="$(mktemp)"
body "$SKILLS_DIR/digest/SKILL.md" > "$DIGEST_BODY"
line_of() { grep -nF "$1" "$DIGEST_BODY" | head -1 | cut -d: -f1; }
DISTILL_AT="$(line_of 'Distill lessons')"
RECONCILE_AT="$(line_of 'fields level')"
INDEX_AT="$(line_of 'generated-only; rewrite wholesale')"
COMPLETION_AT="$(line_of "Append the run's own completion bullet")"
RELEASE_AT="$(line_of 'Release the lock unconditionally')"
for pair in "DISTILL_AT:$DISTILL_AT" "RECONCILE_AT:$RECONCILE_AT" "INDEX_AT:$INDEX_AT" \
            "COMPLETION_AT:$COMPLETION_AT" "RELEASE_AT:$RELEASE_AT"; do
  [ -n "${pair#*:}" ] || err "digest: ordering anchor ${pair%%:*} is missing from the flow"
done
if [ -n "$DISTILL_AT" ] && [ -n "$RECONCILE_AT" ] && [ "$RECONCILE_AT" -lt "$DISTILL_AT" ]; then
  err "digest: the updated: reconcile runs before distillation, so every later append re-stales it"
fi
if [ -n "$INDEX_AT" ] && [ -n "$COMPLETION_AT" ] && [ "$COMPLETION_AT" -lt "$INDEX_AT" ]; then
  err "digest: the completion bullet is written before the INDEX refresh, claiming a completion that may not happen"
fi
if [ -n "$COMPLETION_AT" ] && [ -n "$RELEASE_AT" ] && [ "$RELEASE_AT" -lt "$COMPLETION_AT" ]; then
  err "digest: the lock is released before the run is recorded"
fi
if ! tr '\n' ' ' < "$DIGEST_BODY" | tr -s ' ' | grep -qF 'Reconcile last.'; then
  err "digest: the reconcile-last ordering rule is missing"
fi
if ! tr '\n' ' ' < "$DIGEST_BODY" | tr -s ' ' | grep -qF 'Release the lock unconditionally'; then
  err "digest: lock release must be unconditional, per the schema's same-run release rule"
fi
rm -f "$DIGEST_BODY"

# 11. eval harness: the isolation contract is the whole value. An eval that can silently run
# against the operator's own HOME measures the doctrine in both arms and reports a lie.
EVAL_RUNNER="$ROOT/evals/run.sh"
if [ -f "$EVAL_RUNNER" ]; then
  grep -qF 'ANTHROPIC_API_KEY' "$EVAL_RUNNER" ||
    err "evals/run.sh: the API-key requirement is missing, so a cell could run un-isolated"
  grep -qF 'no un-isolated mode' "$EVAL_RUNNER" ||
    err "evals/run.sh: the refusal to run un-isolated must stay stated in the error"
  # The inverse of the obvious contract. install.sh writes the skills and the doctrine into the
  # cell's *user* source, so excluding `user` strips the treatment and makes both arms
  # identical. Isolation comes from the sandbox HOME. This contract exists because the first
  # version of this runner did exclude it, and every eval would have reported "no effect".
  # Matched per line: a file-wide test is disarmed by any comment that names the flag, and this
  # file discusses the flag in prose directly above the invocation.
  if grep -nE -- '--setting-sources[= ][a-z,]*\bproject\b' "$EVAL_RUNNER" |
     grep -qvE -- '--setting-sources[= ][a-z,]*\buser\b'; then
    err "evals/run.sh: cells must not exclude the user setting source; that is where the doctrine is installed"
  fi
  grep -qF -- '--verify-arm' "$EVAL_RUNNER" ||
    err "evals/run.sh: each cell must verify at run time that its arm loaded the expected skills"
  for arm_marker in 'install.sh" --copy' 'a HOME with no skills'; do
    grep -qF "$arm_marker" "$EVAL_RUNNER" ||
      err "evals/run.sh: the two arms must differ only by the installed skill set ('$arm_marker' missing)"
  done
  # Both halves of harness-root containment. An inherited CODEX_HOME rewrites the operator's
  # real Codex root; a missing sandbox .claude means install.sh finds no harness, the doctrine
  # arm installs nothing, and both arms silently measure the same thing.
  # shellcheck disable=SC2016  # the literal $cell text in run.sh is what we match
  grep -qF 'CODEX_HOME="$cell/home/.codex"' "$EVAL_RUNNER" ||
    err "evals/run.sh: CODEX_HOME must be redirected into the sandbox, never inherited"
  # shellcheck disable=SC2016  # the literal $cell text in run.sh is what we match
  grep -qF 'mkdir -p "$cell/home/.claude"' "$EVAL_RUNNER" ||
    err "evals/run.sh: the sandbox harness root must exist before install, or no skills are installed"
  grep -qF 'the arms would be identical' "$EVAL_RUNNER" ||
    err "evals/run.sh: a doctrine cell must verify that skills were actually installed"
  grep -qF 'evals/score.py' "$EVAL_RUNNER" ||
    err "evals/run.sh: cells must be scored mechanically"
  [ -f "$ROOT/evals/score.py" ] || err "evals: score.py is missing"
  [ -f "$ROOT/tests/test-evals.sh" ] || err "evals: tests/test-evals.sh is missing"
  grep -qF 'tests/test-evals.sh' "$ROOT/.github/workflows/skill-lint.yml" ||
    err "CI: the eval scorer suite is not run"
  grep -qF 'evals/run.sh' "$ROOT/.github/workflows/skill-lint.yml" ||
    err "CI: evals/run.sh must at least be syntax-checked and shellchecked"
  # Live cells cost money and are noisy at small N, so CI may only check the script, never run
  # it. Every workflow is scanned, not just this one, and the runner must appear as an ARGUMENT
  # of bash -n or shellcheck with no command separator in between. Allowing any line that
  # merely contained "bash -n" let `bash -n evals/run.sh && bash evals/run.sh` through, which
  # is the natural way to write "check it, then run it".
  # Remove the sanctioned checker calls from each line first, then look for what is left. A
  # line can hold both a check and an invocation — `bash -n evals/run.sh && bash evals/run.sh`
  # is the natural way to write "check it, then run it" — so asking whether a line *contains* a
  # checker is not the same as asking whether everything on it is one.
  for wf in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
    [ -e "$wf" ] || continue
    if sed -E 's/(bash -n|shellcheck)[^;&|]*//g' "$wf" | grep -q 'evals/run\.sh'; then
      err "CI ($(basename "$wf")): every evals/run.sh mention must be a bash -n or shellcheck argument, never an invocation"
    fi
  done
fi

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
WRITING_LIST="$(sed -n 's/^WRITING_SKILLS="\(.*\)"$/\1/p' "$ROOT/install.sh")"
if [ -f "$CYCLE_INSTALLER" ]; then
  mandated_list="$(sed -n 's/^LEARNING_SKILLS="\(.*\)"$/\1/p' "$ROOT/install.sh") $WRITING_LIST"
  for mandated_skill in $mandated_list; do
    grep -q "^skills = (.*\"$mandated_skill\"" "$CYCLE_INSTALLER" ||
      err "install-prometheus-cycle.sh: 'skills' integrity check omits '$mandated_skill'; the nightly job would activate a doctrine mandating an unverified skill"
    grep -q "^required = {.*\"$mandated_skill\"" "$CYCLE_INSTALLER" ||
      err "install-prometheus-cycle.sh: 'required' visibility gate omits '$mandated_skill'; the nightly job would activate a doctrine mandating an unverified skill"
  done

  # install.sh's uninstall note reads the route-proof trace the cycle installer writes. The two
  # path literals must stay identical, or the note silently never fires again.
  INSTALL_PROOF="$(sed -n 's/^ROUTE_PROOF_TRACE="\(.*\)"$/\1/p' "$ROOT/install.sh" | head -1)"
  CYCLE_PROOF="$(sed -n 's/^ROUTE_PROOF_FILE="\(.*\)"$/\1/p' "$CYCLE_INSTALLER" | head -1)"
  if [ -z "$INSTALL_PROOF" ] || [ "$INSTALL_PROOF" != "$CYCLE_PROOF" ]; then
    err "route-proof path drift: install.sh reads '$INSTALL_PROOF' but install-prometheus-cycle.sh writes '$CYCLE_PROOF'"
  fi
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

# 10. skill inventory agreement: every skill has a doctrine routing row and a README entry, and
# the README's repo-layout count matches the tree. A skill added without propagating it to those
# copies is silent drift that no reader notices (reel-maker, PR #7, shipped exactly that way).
routing_rows() { # routing_rows <doctrine-file>: the table between **Routing.** and the END marker
  awk '/\*\*Routing\.\*\*/{f=1; next} /END BORROWEDFIRE DOCTRINE/{f=0} f' "$1"
}
# The Skill column only (the last cell of each row). A backticked mention inside a Need cell must
# not satisfy or violate a routing contract.
routing_skill_cells() { # routing_skill_cells <doctrine-file>
  routing_rows "$1" | awk -F'|' 'NF >= 3 {print $(NF-1)}'
}
# Reduced mode drops the automatic-learning mandate (reflect) and the writing-skill mandates, so
# exactly those skills have no reduced-mode routing row. Every other skill appears in both tables.
# The exemption is two-sided: a dropped-mandate skill routed in the reduced table would route an
# unverified skill, the defect class the reduced doctrine exists to prevent.
REDUCED_ROUTING_EXEMPT="reflect $WRITING_LIST"
for name in $SKILL_NAMES; do
  routing_skill_cells "$DOCTRINE" | grep -qF "\`$name\`" ||
    err "doctrine: routing table has no row for '$name' (add one, or record the exemption here)"
  case " $REDUCED_ROUTING_EXEMPT " in
    *" $name "*)
      if routing_skill_cells "$SAFE_DOCTRINE" | grep -qF "\`$name\`"; then
        err "reduced doctrine: must not route '$name' (its mandate is dropped in reduced mode)"
      fi
      ;;
    *)
      routing_skill_cells "$SAFE_DOCTRINE" | grep -qF "\`$name\`" ||
        err "reduced doctrine: routing table has no row for '$name'"
      ;;
  esac
  grep -qF "skills/$name/SKILL.md" "$ROOT/README.md" ||
    err "README.md: no entry links skills/$name/SKILL.md"
done
# Reverse direction: a routing row or README link must point at an existing skill. A deleted
# skill whose row or link survives is the same silent drift, inverted.
for doctrine_file in "$DOCTRINE" "$SAFE_DOCTRINE"; do
  # shellcheck disable=SC2016  # backticks are intentional literal table text
  while IFS= read -r cell_name; do
    [ -n "$cell_name" ] || continue
    case "$cell_name" in
      *[!a-z0-9-]*)
        err "$(basename "$doctrine_file"): malformed skill reference '$cell_name' in a routing Skill cell"
        ;;
      *)
        [ -d "$SKILLS_DIR/$cell_name" ] ||
          err "$(basename "$doctrine_file"): routing table routes '$cell_name' but skills/$cell_name does not exist"
        ;;
    esac
  done < <(routing_skill_cells "$doctrine_file" | grep -oE '`[^`]+`' | tr -d '`' | sort -u)
done
while IFS= read -r readme_target; do
  [ -n "$readme_target" ] || continue
  [ -f "$ROOT/$readme_target" ] ||
    err "README.md: links $readme_target which does not exist"
done < <(grep -oE 'skills/[A-Za-z0-9._-]+/SKILL\.md' "$ROOT/README.md" | sort -u)
ACTUAL_COUNT="$(echo "$SKILL_NAMES" | wc -w | tr -d ' ')"
STATED_COUNT="$(sed -n 's|^skills/[[:space:]]*\([0-9][0-9]*\) SKILL\.md skills.*|\1|p' "$ROOT/README.md" | head -1)"
if [ -z "$STATED_COUNT" ]; then
  err "README.md: the repo-layout 'skills/  N SKILL.md skills' line is missing"
elif [ "$STATED_COUNT" != "$ACTUAL_COUNT" ]; then
  err "README.md: repo layout says $STATED_COUNT skills, the tree has $ACTUAL_COUNT"
fi

# 12. private brain content must never land in this public repo (doctrine: Memory). Machine
# names, home paths, and brain page counts are the shapes that leaked before this guard: they
# arrive inside otherwise-legitimate evidence in the land log and review notes, where prose
# review reads them as detail rather than disclosure.
#
# Two precision rules, both learned by getting them wrong:
#   Scan the directory, not the git index. Reading the index is the tighter definition of
#   "publishable", but `git grep` resolves through a copied worktree's .git file to the ORIGINAL
#   repository, so a clone would be linted against a tree it does not contain. The walk costs a
#   false positive on an untracked scratch file, and that error names the file and its line.
#   Exempt exactly the placeholder forms. Excluding a word like "example" or "fixture" exempts
#   every real leak on a line that happens to contain it, and every leak in a path that happens
#   to contain it. The only content exemptions are placeholder paths and this file's own test
#   helper invocations, which carry the leak shapes as literal fixture data.
PRIVATE_RE='/(Users|home)/[a-z][a-z0-9._-]*|[0-9]+ lessons, (the )?tree has|INDEX (says|reports) [0-9]+'
# shellcheck disable=SC2016  # the literal $HOME and ${ text are intentional placeholder forms
PLACEHOLDER_RE='\$HOME|/(Users|home)/(<|\$|\{)|leak_[a-z_]*case "'
PRIVATE_HITS="$(grep -rnE "$PRIVATE_RE" \
  --include='*.md' --include='*.sh' --include='*.py' --include='*.yml' --include='*.yaml' "$ROOT" 2>/dev/null |
  grep -vE "$PLACEHOLDER_RE" || true)"
if [ -n "$PRIVATE_HITS" ]; then
  printf '%s\n' "$PRIVATE_HITS" | head -5 | while IFS= read -r hit; do echo "       $hit" >&2; done
  err "private content: a home path or brain page count appears in a scanned file; keep host and brain specifics in the private brain"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "skill-lint: $ERRORS error(s)" >&2
  exit 1
fi
echo "skill-lint: OK ($ACTUAL_COUNT skills)"
