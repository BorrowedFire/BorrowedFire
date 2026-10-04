<!-- BEGIN BORROWEDFIRE DOCTRINE -->
## Borrowed Fire doctrine (v8 reduced mode — managed by install.sh, do not hand-edit)

**Memory.** Prometheus is the private git-backed brain. Resolve it through `$PROMETHEUS_DIR`, then
`~/.config/borrowedfire/brain`, then `~/prometheus`. Before substantive repo work, use `recall` for
the matching project and lessons pages. Use `remember` for durable decisions, gotchas, people,
meetings, and project-status changes; it owns storage, outbox, schema, and sync behavior. Never put
secrets or private brain content in a product repo.

**Writing.** Write so a tired engineer understands on the first read. Every reply, doc, commit
message, PR body, and owner brief follows the same rules. Carry one thought per sentence and one
instruction per sentence. Use active voice with a named actor. Pick the short everyday word. Put
the condition before the instruction. Give each thing one name and use it everywhere. Delete every
word that does no work. Keep the articles and the small words that make a sentence parse one way.
Prefer a period to an em dash or a semicolon. Scope every "never" and "always" to its hazard and
name the sanctioned exceptions, so a rule cannot forbid an operation the system requires. The
writing skills are not mandated in this state because the installer could not verify them. Apply
the rules above by hand until a successful Borrowed Fire install restores the full doctrine.

**Tests.** Before adding a test, name the behavior or independent contract it protects, the
credible regression that makes it fail, and why existing coverage misses that regression. Extend
existing cases when they cover the same risk. A small edit with no uncovered risk needs no new test.
Judge test cleanup by retained protection. A reduction target or unchanged code coverage does
not justify losing the only test of a current contract.

**Reduced mode.** Part of the Borrowed Fire skill stack is not installer-owned, so this context
carries only the capabilities the installer could verify. Automatic learning is disabled and the
writing skills are not mandated. The installer's error names the exact skill that failed
verification. Restore the full doctrine with a successful Borrowed Fire install before you enable
any recurring learning controller. Do not invoke `reflect` automatically in this state.

**CI.** Run CI locally unless a check explicitly requires a GitHub-only capability. Read the
repository's workflow commands and reproduce their setup, flags, and environment for the current
candidate. Record the commands, candidate, results, and any coverage gaps. Do not ask the owner to
enable Actions, buy minutes, raise spending limits, or approve hosted CI for checks that can run
locally. Missing local tools or capacity are local blockers, not automatic hosted exceptions.
For an exception, name the exact check and the GitHub-only capability it needs. Keep required
Codex PR review separate from CI. If branch protection requires a hosted status, report that
specific merge blocker once; do not bypass protection, fabricate a status, or repeatedly ask for
Actions funding. Changing workflows or protection requires task-specific authorization.

**Review and repair.** Record the requested outcome and acceptance checks before implementation.
Before review, record the frozen candidate, affected paths, evidence, and blocking criteria. Give
all required reviewers the same candidate and scope. Required gates must cover the final candidate.
Reuse valid evidence for unchanged code and run affected checks and required integration gates.

Validate findings with a safe reproduction or precise code and contract evidence. A finding blocks
only if it prevents the requested outcome, fails an acceptance check, demonstrates a regression
introduced by the change, or establishes a concrete security, safety, or data-integrity failure
in affected behavior. Record other valid findings as follow-ups. Findings do not widen scope.

Allow three submitted review batches or 60 elapsed minutes from the first submission, whichever
ends first. One batch sends one frozen candidate to all required reviewers and combines their
findings. Every retry or resubmission counts, even without code changes. Record submissions,
candidates, start time, and deadline in durable task evidence. Carry the budget across reviewers,
branches, machines, and sessions. Investigation and "until green" do not reset it. Elapsed time
includes repairs, investigation, verification, and waits. When a second validated finding
eligible for in-loop fixing under the authorized scope and `land` release-branch policy concerns
the same behavior, investigate the shared cause within the affected contract and its relevant
producers and consumers. On release/beta/hotfix/signing branches, group related nonblocking
findings into a main-branch follow-up with the shared-cause question. Do not delay the branch to
investigate that follow-up. Keep corrections within the authorized scope and remaining budget.

Collect the final allowed batch within the remaining time. When it completes or the deadline
arrives, stop new edits, investigations, checks, retries, review requests, and polling. Safely
cancel work that can be cancelled. Record other unfinished work as pending, neither pass nor fail.
If all required gates pass, complete the already-authorized action. Otherwise, distinguish a
confirmed defect, missing required evidence, and an owner decision. Do not waive gates, merge
with blockers, or call a candidate ready while a required gate is pending.

State what fails or remains unverified. Recommend approval or deferral using the evidence,
whether the change caused the issue, and the consequence of deferring it. For more work, specify
the smallest repair, investigation, or scope reduction, its success check, and its additional
time and review budget. Only an explicit owner extension authorizes that named work. Record each
approved extension's activation timestamp and its own deadline. Count its time from activation,
without adding minutes retroactively to an expired deadline. Preserve the original accounting.
An extension does not authorize unrelated work. Use `land` for the PR review procedure.

**Safety.** The `land` denylist is always owner-gated: migrations/schema/RLS, auth, payments,
secrets/signing, destructive operations, deploys/releases, and store submission. A workflow skill
never widens the owner's existing authorization.

**Fleet.** Let the active workflow and the private `config/fleet.md` choose eligible tiers.
Judgment stays with the current capable harness; bounded volume work defaults to a configured
local tier when one is available. Never hardcode private endpoints, caps, or provider policy.

**Routing.**

| Need | Skill |
|---|---|
| capture / retrieve / consolidate memory | `remember` / `recall` / `digest` |
| land one PR through review | `land` |
| work a registered repo/fleet queue | `maintainer` |
| commit/push/merge/deploy closeout | `ship` |
| undo a bad merge or deploy | `rollback` |
| App Store / Play release train | `store-release` |
| changelog or release notes | `changelog` |
| dependency/security updates | `deps` |
| shape a report or idea into an issue | `triage` |
| register a new repo/app/idea | `bootstrap` |
| bounded QA loop | `qa-audit` |
| test value, duplication, or a pruning campaign | `test-audit` |
| marketing / customer-facing copy | `signal` |
| short-form marketing video or reel | `reel-maker` |
| audit requested vs completed work at session end | `session-closeout` |
<!-- END BORROWEDFIRE DOCTRINE -->
