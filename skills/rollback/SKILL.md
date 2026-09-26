---
name: rollback
description: Undo an authorized bad merge or deployment and verify recovery. Use when rollback is requested or an incident needs a recovery plan.
---

# Rollback

Restore a known-good state fast, prove it live, then learn from it. Speed matters, but a rollback
that isn't verified live is just a second unverified deploy.

## Action scope

For a recovery-plan request, inspect available evidence, identify the proposed revert or
fix-forward path, and report the steps and missing approvals. Stop before creating a revert,
merging, or deploying. A plan request does not authorize those actions.

For an execution request, carry forward the owner's existing grants. Before each mutation,
check that the grant covers the target and action. Continue authorized preparation when a later
merge, deployment, schema, or destructive action still needs approval. Preserve `land`'s owner
gates and the repository's release rules.

## Revert vs fix-forward (decide first, say so)

- **Roll back** when the break is user-facing/severe, the bad change is isolated (one merge, one
  deploy), and reverting is cheap and safe.
- **Fix forward** (via `land`) when the revert itself is risky — schema already migrated, data
  written in the new shape, other work stacked on top. A revert that fights a migration is worse
  than a targeted fix.
- When data/schema is involved, verify that the old code can consume the current data before
  choosing rollback. Reverting a migration remains owner-gated under land's denylist.

## Rules

- Work from evidence: reproduce or observe the breakage before acting (error, log line, failing
  route) — a rollback on a hunch can destroy a good deploy during an unrelated incident.
- Revert with history. Inspect the target commit's parents first. A squash or ordinary commit
  uses `git revert <sha>`. A merge commit needs an explicitly verified mainline parent with
  `git revert -m <parent> <sha>`. Do not guess the parent. Never force-push or reset a shared branch.
- Re-deploy through the same repo-native path `ship` used — no ad-hoc production surgery.
- Verify recovery with the **same live evidence class that failed**: if a route 500'd, that route
  200s; if an RPC misbehaved, the RPC now returns the expected shape.
- If the rollback itself fails or the breakage persists after revert, stop and escalate
  decision-ready — the diagnosis was wrong; don't chain guesses in production.

## Flow

1. **Situation.** What broke, when, blast radius, the suspect sha(s)/deploy. `recall` the repo's
   `lessons/` — repeat incidents are common.
2. **Decide** revert vs fix-forward (rules above); state the choice and why in one line.
3. **Scope check.** For a plan request, report the proposed actions and stop. For execution,
   confirm which actions the existing grant covers before continuing.
4. **Revert, when authorized.** `git revert` the merge/commit(s) on a branch; PR through the repo's normal checks
   (expedited, but never skipped). Merge only when authorized and the `land` gates pass.
5. **Re-deploy, when authorized,** through the canonical path. A revert grant alone does not
   authorize deployment.
6. **Verify live.** Same evidence class as the failure, plus a quick pass over adjacent surfaces.
7. **Report.** Timeline (broke → detected → reverted → verified), the revert sha, residual risk,
   and the exact re-land path for the original change.
8. **Postmortem capture** after execution: `remember` a `lessons/` page — trigger, root cause if known,
   what would have caught it earlier — wikilinked to `[[projects/<repo>]]` and the reverted
   change. This is the write-back that makes the next incident shorter.

## Related

`ship` (the forward path; its verification failure is this skill's trigger) · `land` (fix-forward
and re-landing the corrected change) · `store-release` (halting staged store rollouts) ·
`remember` (postmortem capture).
