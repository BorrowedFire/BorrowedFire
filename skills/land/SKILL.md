---
name: land
description: Take one authorized branch or PR through review, fixes, proof, and merge. Preserve existing owner gates. Excludes deployments and store releases.
---

# Land

Drive a branch from "I have a change" to **merged · clean · proven** without babysitting. The value
is **reliability + encoded gotchas + decision-ready escalation**, not the happy path. Three gates
stand before merge: **adversarial review · Codex · live proof.** Bias toward escalating ambiguity
over guessing.

## Local CI

Run CI locally unless an exact check requires a GitHub-only capability. Follow the doctrine's CI
rule. Read the workflow and reproduce its commands, setup, flags, and environment on the current
candidate. Record results and gaps. A local pass does not prove an omitted check passed.
Do not request Actions funding or hosted execution for locally runnable checks. A missing local
tool is a local setup problem, not a GitHub requirement. Keep Codex PR review as a separate gate.
If GitHub protection requires a hosted status, report the exact merge blocker once. Do not bypass
protection or repeatedly ask the owner to enable Actions.

## Operating principle — Decision-Ready

Complete authorized preparation and required checks within the review budget below. Resolve
routine decisions yourself. Ask only for an unmet owner gate, a material choice, exact access,
or a specific bounded extension supported by evidence. A blocked candidate can be ready for an
owner decision without being ready to merge. Never label missing proof or pending review as green.
Do not ask to continue merely because a reviewer suggested more work.

## Classify first

Before adding or changing a test, name the behavior or independent contract it protects, the
credible regression that makes it fail, and why existing coverage misses that regression.
If no distinct risk needs protection, add no test. Extend an existing case
when it covers the same risk. Keep review and fixes within the authorized change. A landing
task does not start a test-pruning campaign.

- **Autonomous** — clear, bounded, reproducible, with a real **live-proof path**. Drive to merge.
- **Needs-owner** — product choice, security/privacy/irreversible call, missing credential/access,
  no live proof, or it touches the **denylist** ([denylist](references/denylist.md), plus the project
  registry's `denylist_extra`). Drive to decision-ready, then emit one Owner Decision Brief.
- **Ignored** — only when the owner explicitly said so. Leave it untouched.

## Runtime capabilities

Before dispatch or review, read [references/runtime-capabilities.md](references/runtime-capabilities.md).
Resolve mechanics from the tools this session exposes and the configured fleet. A missing tool
does not waive a review gate. Use the repository's branch convention, or `<harness>/<slug>`.

## Inputs

`/land [branch] [flags]` (or the harness's skill-invocation equivalent)

| Flag | Default | Effect |
|---|---|---|
| `branch` | current | Branch to land. |
| `--no-auto-merge` | auto-merge **ON** | Stop at the merge gate for owner approval. |
| `--max-rounds N` | `3` | Maximum submitted review batches for this change; retained flag name. Raising the limit requires an explicit owner grant. |
| `--max-review-minutes N` | `60` | Elapsed review-and-repair budget from the first review submission. Raising the limit requires an explicit owner grant. |
| `--reviewer` | `codex` | `codex` requests both review gates. `adversarial-only` prepares local review and proof; it permits merge only when the registry explicitly says `review_bot: none`. |

Default posture: **auto-merge ON** for Autonomous low/medium-risk diffs; **always owner-gated** for
the denylist.

## Review budget and evidence

Use `--max-rounds` as the submitted-batch limit and `--max-review-minutes` as the elapsed-minute
limit, defaulting to **3 batches and 60 minutes**. Stop when either active limit is reached.
Apply any supplied lower limit; a higher limit requires the explicit owner grant described above.
A batch sends one frozen candidate to all required reviewers under the same scope and blocking
criteria, with one request per required reviewer. Reserve its number
before the first submission and record all requests in it. Start the clock at that first
submission. A failed or unavailable submission still consumes the batch once attempted;
preparation before dispatch does not.

Count retries, replacement reviewers, refutation-only re-reviews, and reviews without edits.
Parallel required reviewers share one batch. Any new request after that batch's planned
submissions consumes another batch. Changing reviewers, branches, machines, tools, sessions,
or investigating a shared cause does not reset the count or clock. "Until green" is not an
extension. Import the recorded limits, prior batches, and first-submission time when resuming
the same change.
If the history cannot be established, report the missing ledger; do not assume a fresh budget.

Keep a durable review ledger in the PR or existing land log: authorized outcome, acceptance
checks, scope baseline, candidate commit or content fingerprint, configured limits, first-submission
time and deadline, submitted batches and reviewer requests, findings with disposition, and gate
evidence. Set the initial deadline to the first-submission time plus the configured minute limit.
Do not modify the frozen candidate while its batch is running. Record results against its exact
revision. Reuse valid verification for unchanged behavior, but run checks affected by edits and
required integration gates. Both review gates must cover the final candidate.

The last permitted batch may finish before the active deadline. After its results arrive,
start no further repairs, investigations, checks, or review requests. At the elapsed deadline,
stop new edits, checks, investigation, review requests, waits, and polling, including for a pending
final batch. Safely cancel work that can be cancelled. Record the latest available evidence and
unfinished work that cannot be cancelled as pending. A cancelled check supplies no pass or failure
evidence. Never cancel a running operation unsafely or convert pending evidence into a verdict.
Reporting and an already-authorized merge with all gates satisfied remain allowed.

At either limit, use step 8's disposition. An owner extension must name the issue, allowed work,
additional batches and minutes, and success check. Record the explicit grant and its named scope.
Immediately before resuming the approved work, record an activation timestamp and a new deadline
of activation plus the granted minutes, unless the owner specified an earlier absolute deadline.
Do not add minutes retroactively to an expired deadline. Retain the original start, deadline,
batch count, usage, and evidence; track the extension's allowance and usage separately in the same
ledger. The extension applies only to its named work and does not reopen the whole task.

## The loop

**0 · Preflight.** Confirm `gh` auth + repo; `recall` the brain's `lessons/` and the repo's
`projects/` registry page (autonomy level, `review_bot`, `denylist_extra`) if a brain is
available; identify the diff's **blast radius** — needed for the denylist check, the live-proof
choice, and the summary. **Freeze a scope baseline**: original request, changed-file list,
non-test LOC count, acceptance checks, and blocking criteria. The circuit-breakers below measure
against this snapshot, not against whatever the diff has grown into. **Release-branch mode**: on
a release/beta/hotfix/signing branch, only release blockers, install/upgrade breakage, data loss/crashes, and concrete security
exposure get fixed in-loop; every other finding is filed as a main-branch follow-up. Every
follow-up this skill files — here, at the invariant-audit grouping in step 7, and at the
non-convergence classification in step 8 — is written in the brain with the canonical
`follow-up:` token, its action, and its trigger (schema §Follow-ups), so `digest` lists it and
`maintainer` can pick it up. A deferral recorded only in a PR comment is invisible the moment
the tab closes.

**1 · Un-stale the branch (critical).** `git fetch origin`; if behind the base branch, **merge it
in** first. A stale branch makes the reviewer flag files that exist on the base but not the branch
as "missing/untracked" — phantom findings. If the base merge **conflicts**: resolve only trivial,
mechanical conflicts (imports, adjacent-line churn, lockfiles by regeneration); any conflict
touching the same logic the branch changes is a *semantic* conflict — stop and escalate
decision-ready rather than guessing an integration.

**2 · Scan + commit + push + PR.** Before the first push or external review bundle, scan the exact
outgoing commits and uncommitted changes for keys, tokens, credentials, and `.env` content. Use the
repository's secret scanner when present and inspect the outgoing files. A detected secret stops
publication until it is removed from every outgoing commit. Scan again when later edits or commits
change the outgoing content. Verify scanner findings; a documented inert fixture may be a false
positive, but uncertainty does not permit publication. Commit intended changes (clear message). Push. Open the PR if missing —
body = problem / root cause / fix / **how it was proven** / scope. Use full clickable URLs, never
bare `#123`.

**3 · Freeze and submit a review batch.** Check the remaining budget. Complete step 2 for every
revised candidate: scan outgoing content, commit the intended changes, and push them. Confirm that
no intended candidate changes remain uncommitted and the PR's remote `headRefOid` matches the
local candidate commit (`git rev-parse HEAD`). If they differ, resolve the mismatch within budget
before submitting either review. Preserve unrelated local work.

Record that exact commit, affected paths, verification evidence and gaps, scope, and blocking
criteria in the ledger. Submit this same candidate and review contract to the independent
adversarial reviewer (gate #1) and Codex (gate #2) through steps 3–4.
Complete required checks and step 9's proof before submitting the last permitted batch.
The adversarial reviewer must be independent of the author. Do not apply findings between the
two submissions. If the candidate changes, both gates need a new batch on that candidate.

**4 · Trigger Codex (gate #2).** Record baseline comment/review counts before requesting review.
Use `gh pr comment <PR> --body "@codex review"`. A push alone does not re-trigger review.
Each new request, including a retry or refutation-only request, belongs to a counted batch.
Skip this gate only when the registry says `review_bot: none`; the merge gate then requires
adversarial review satisfying step 6 + live proof + CI, and the summary must say the Codex gate
was absent.

**5 · Wait for the batch.** Use supported events or bounded polling until results arrive or the
elapsed deadline is reached. Bound every wait by the remaining time and the runtime's
communication limits. The bot login matches `codex` (e.g. `chatgpt-codex-connector`). Bot behavior
details here were observed as of 2026-07; re-verify changed comment shapes before trusting them.
Collect every required review before changing the candidate. A missing result is pending.

**6 · Read the verdict — DUAL SIGNAL (load-bearing).**
- **NO-FINDINGS RECEIPT** = an issue comment "Didn't find any major issues … **Reviewed commit: `<sha>`**".
  The SHA must match the frozen candidate and current head. A mismatch is stale evidence;
  another request consumes a batch and requires remaining budget.
- **FINDINGS** = inline review comments (`gh api repos/<repo>/pulls/<PR>/comments`), each tagged
  P1/P2/P3. Verify their candidate before acting on them.
- Check both signals. Record each review receipt with its candidate revision.

A completed review of the exact frozen candidate satisfies this skill's review gate when it
reports no findings or every finding has an evidence-backed disposition with no applicable
blocker remaining. A completed review containing only documented nonblocking suggestions does
not require another review. Preserve the actual reviewer verdict and the agent's disposition
separately; never relabel a missing, partial, or stale review as complete. Repository-required
approvals, statuses, and change-request resolution remain mandatory. This classification cannot
satisfy or override them.

**7 · Handle findings from the complete batch.** A finding is a claim, not a fact. Combine
findings from all reviewers, verify them, and record their disposition before editing.
- **Blocker:** evidence shows that the issue prevents the requested outcome, fails an acceptance
  check, demonstrates a regression introduced by the change, or establishes a concrete security,
  safety, or data-integrity failure in affected behavior. Use a safe reproduction or precise
  code and contract evidence; never require an unsafe live reproduction.
  Explain the failing case and impact. Fix only within authorized scope and remaining budget,
  then run affected checks and return to step 2 to scan, commit, and push the repaired candidate.
  Confirm its remote PR head in step 3 before requesting both reviews in a new batch.
- **Valid nonblocking finding:** a real improvement that does not meet the blocking criteria. Record it
  with its trigger; do not expand this task or seek another review to address it. A review is
  complete for this task under step 6 when no applicable blockers remain; unrelated suggestions
  do not create blockers. Preserve the actual verdict and disposition in the ledger.
- **False or stale:** preserve correct code and record an evidence-backed refutation. If a
  required gate still lacks a completed current-candidate review or requires reviewer action,
  another review request consumes a batch.
- **Owner decision:** explain the product, scope, security, or other authorization choice in
  one Owner Decision Brief. A finding never grants authority to fix it.

**Related-finding circuit breaker (mandatory).** The second validated finding in the same
behavior stops comment-by-comment patching. Within the remaining budget, perform a bounded
invariant audit of that behavior before another repair.

Only findings **eligible for in-loop fixing** under the frozen scope and release-branch rule
in step 0 count toward this trigger. On a release/beta/hotfix/signing branch, group related
non-blockers into one main-branch follow-up with the shared-cause question. Do not delay the
release branch to investigate that follow-up.

1. Name the affected contract, its authoritative owner/state transition, and the failing cases.
2. Trace the relevant producers and consumers of that contract. Inspect lifecycle, identity,
   retries, or legacy state only where the evidence connects them to the failure. Record gaps.
3. Identify the smallest correction within scope. Add or extend tests only for credible
   uncovered regression risks; run affected checks and required integration gates.
4. Record the cause, correction, evidence, and any unsupported states before another batch.

The audit uses the same time and batch budget. It does not require an exhaustive inventory of
unrelated entry points or adjacent suites. If it cannot be bounded within authorized scope and
remaining time, record what is established and use step 8. Do not start a wider redesign.

**8 · Stop and classify.** Stop further repair and review when the batch or elapsed budget ends,
or earlier when any of these occurs:
- Two consecutive completed batches expose new blockers in the same behavior without convergence.
- A new validated related finding surfaces after the invariant audit and subsequent re-review.
- The same finding recurs after a genuine fix.
- Cumulative fixes push the diff past 2× the frozen baseline (files or non-test LOC) without an
  explicit owner scope expansion.

Use existing evidence to select an outcome. If all required gates pass and only non-blocking
follow-ups remain, complete the already-authorized merge without asking for more work. Otherwise
classify each outstanding item as a confirmed defect, missing required evidence, or owner
decision. Report follow-ups separately. Never merge with an unresolved blocker or unmet gate.

Recommend the smallest next step: defer the non-blocker, repair a named defect, obtain specific
missing evidence, or narrow the change. For any proposed extension, give the failing case and
supporting evidence, whether this change caused it, consequences of deferral, exact allowed work,
success check, and additional batches and minutes. Say whether you recommend approving or
deferring it. Do not ask vaguely to "continue" or treat the limit itself as a reason for more work.

A denylist trigger changes the item to Needs-owner. Stop actions that need ungranted permission.
Continue only authorized preparation within the remaining budget and preserve the merge gate.
A proof requirement does not grant permission to change a live system or deploy a candidate.

**9 · Live Proof Gate (gate #3) — pre-merge, not optional.** Prove the *exact final candidate*
works through its real changed path. **Never infer a waiver from "review clean" or "tests pass."**
- **UI diff** → drive the real surface (sim/app/browser), screenshot, confirm.
- **Backend / data / migration** → query the **live system** and confirm behavior (RPC output,
  grants, row counts, state transition).
- **Jobs / notifications / external calls** → trigger the real path and observe the result class.
- **Pure docs / metadata / CI** → built-artifact or workflow proof, and *state why* there's no
  runtime boundary.
- Re-run proof after **any** fix that touches the runtime path. Record concrete evidence
  (command + observed state) in the PR + summary; redact secrets.

**Proof ladder — every recorded proof names the rung it reached:**
1. Claimed it. Worthless on its own.
2. Pointed at the line: a real `file:line`, or the library's own source.
3. Walked the failure step by step and showed the bad case cannot reach.
4. Ran it: a command, script, or test that exercises the exact changed path and fails loud if
   the claim is wrong. A generic green suite does not reach this rung.
5. Reproduced it on the real changed surface (sim, app, browser, or live system).

A runtime-path claim passes this gate at rung 4 or higher. The class bullets above pick the
surface: where a bullet names a live system or a drivable surface, that class's floor is rung 5.
The docs/metadata/CI bullet is already a rung-4 path: the built artifact or workflow run is the
executed check. A claim stuck below rung 4 is **unproven**. Record it as unproven in the PR and
the summary, and treat the gate as not passed. Never round up.

**10 · Merge gate.** Squash-merge only when all hold: adversarial and Codex reviews satisfy step 6
on the same current head (or `review_bot: none` is acknowledged for Codex); no applicable blocker
remains; live proof is recorded and passed at the rung floor for its class; required CI/tests,
repository approvals, and statuses pass; the diff is outside the denylist. Keep raw review
verdicts and dispositions visible. If `--no-auto-merge`, stop here with a brief.

**11 · Close out.** Include any repository land-log entry in the candidate before its final review
and proof. Record the item, classification, decisions, and evidence known then. Do not claim the
entry's own commit has already passed review. Record the actual merge SHA and final gate receipts
in the PR summary or the private project log after merge. Do not create an unreviewed repository
commit just to add the merge SHA. Write any new gotcha / false-positive pattern back via `remember` to the brain's
`lessons/`, wikilinked to `[[projects/<repo>]]` (outbox fallback if the brain is unreachable) — so
the next run, on any machine, needs the owner less.

## Reviewed fleet updates

When landing a Borrowed Fire update that the owner authorized for automatic installation, promote
it only after the merged tree matches the reviewed candidate and all gates pass. Use `remember`
to update the private `notes/borrowedfire-release-channel.md` record. Set `release_commit` to the
full published merge SHA, `release_status` to `approved`, and `review_url` to the reviewed PR.
Keep the old revision in its dated log. A branch push, passing CI, or an unreviewed main commit
cannot authorize installation. Never promote an arbitrary remote revision just to clear an
updater warning. Use the fleet updater status to verify each reachable machine.

## High-risk denylist — ALWAYS owner-gated at merge (even with auto-merge ON)

See [denylist](references/denylist.md) (authoritative) plus the project registry's `denylist_extra`. Drive to
clean + proven within budget, then **stop at the merge gate**. At a budget limit, use step 8
even if the candidate still needs work.

## Authorization boundaries

Invoking land authorizes the full chain *except* the denylist. Still: push ≠ a license to
scope-creep; CI-fix stays within the PR's intent; stop cleanly at the last authorized boundary and
report the exact next action. Deploys and release/build cuts are never in scope (`ship` /
`store-release`).

Within the authorized scope and remaining budget, continue through implementation, fixes, and
required verification. Carry prior grants forward without repeated approval. Stop at an unmet
owner gate, unavailable required evidence, a budget limit, or a decision that changes scope.

## Owner Decision Brief (the only thing you ever send the owner)

Use the latest available evidence; refresh it before asking only while budget remains. State
when each receipt was observed. Never re-ask something already answered or present a blocked
candidate as ready to merge. A decision-ready brief must state what remains blocked. Each brief:
- full **clickable URL + title**;
- plain-language **what changes & who benefits**;
- **why the decision is needed now**;
- **completed proof** — repro, live proof, tests, adversarial + Codex, CI, mergeability;
- **tradeoffs / residual risk / missing evidence**;
- **your opinionated recommendation + rationale** (don't offload the analysis);
- the **exact choices**, including defer, narrow the change, or a named bounded repair when
  applicable. For more work, include step 8's evidence, recommendation, success check, and
  additional time and batch allowance. Never offer an open-ended restart.

## Summary (trust mechanism — it auto-merged before they read it)

```
## Land: <branch> → <merged sha | escalated | stopped>
Class: <Autonomous|Needs-owner> · Gates: adversarial <…> · Codex <satisfied@sha; actual verdict> · Budget: <N batches, elapsed/deadline> · live-proof <…> · CI <…>

### ⚠️ Decisions worth a look
- Refuted Codex <P?>: "<claim>" — evidence: <…>               (no code change)
- Auto-fixed <file>: <what + why it matched shipped reality>  (<sha>)
- Auto-merged <non-trivial PR>                                (revert: git revert <sha>)

### Live proof
- <command/path → observed result · rung N; redacted>

### Routine (collapsed) · Lessons written back
```
Lead with revert-worthy calls; give a sha for every autonomous edit/merge so undoing one is one
command (`rollback` consumes these).

## Honest ceiling

Checks establish only the properties they exercise. Review and proof can still miss defects.
Verify findings before editing, tie evidence to the final candidate, and report missing evidence.

## Related

`maintainer` (orchestrates many lands) · `ship` (deploy closeout) · `rollback` (undo a bad land) ·
`remember`/`recall` (lessons write-back/preflight) · [denylist](references/denylist.md).
