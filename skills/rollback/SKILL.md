---
name: rollback
description: Undo a bad merge or deploy and prove recovery — the inverse of `ship`. Use when the user says "/rollback", "rollback", "roll it back", "revert the deploy", "that release broke production", "undo that merge", or when `ship`'s post-deploy verification fails, or `land`'s summary flags an auto-merge worth reverting. Reverts code, re-deploys the last good state, verifies recovery live, and writes the postmortem lesson. NOT for landing fixes forward (`land` — often the better choice; this skill says when) and NOT for halting store rollouts (`store-release` owns store mechanisms).
---

# Rollback

Restore a known-good state fast, prove it live, then learn from it. Speed matters, but a rollback
that isn't verified live is just a second unverified deploy.

## Revert vs fix-forward (decide first, say so)

- **Roll back** when the break is user-facing/severe, the bad change is isolated (one merge, one
  deploy), and reverting is cheap and safe.
- **Fix forward** (via `land`) when the revert itself is risky — schema already migrated, data
  written in the new shape, other work stacked on top. A revert that fights a migration is worse
  than a targeted fix.
- When data/schema is involved, reverting **code** is usually safe; reverting a **migration** is
  denylist territory (`land`'s `references/denylist.md`) — owner-gated, always.

## Rules

- Work from evidence: reproduce or observe the breakage before acting (error, log line, failing
  route) — a rollback on a hunch can destroy a good deploy during an unrelated incident.
- Revert with history, never rewrite: `git revert <sha>` (land's summaries and ship's reports give
  the sha — one command by design). Never force-push; never `reset` a shared branch.
- Re-deploy through the same repo-native path `ship` used — no ad-hoc production surgery.
- Verify recovery with the **same live evidence class that failed**: if a route 500'd, that route
  200s; if an RPC misbehaved, the RPC now returns the expected shape.
- If the rollback itself fails or the breakage persists after revert, stop and escalate
  decision-ready — the diagnosis was wrong; don't chain guesses in production.

## Flow

1. **Situation.** What broke, when, blast radius, the suspect sha(s)/deploy. `recall` the repo's
   `lessons/` — repeat incidents are common.
2. **Decide** revert vs fix-forward (rules above); state the choice and why in one line.
3. **Revert.** `git revert` the merge/commit(s) on a branch; PR through the repo's normal checks
   (expedited, but never skipped); merge.
4. **Re-deploy** the reverted state through the canonical path.
5. **Verify live.** Same evidence class as the failure, plus a quick pass over adjacent surfaces.
6. **Report.** Timeline (broke → detected → reverted → verified), the revert sha, residual risk,
   and the exact re-land path for the original change.
7. **Postmortem capture** (always): `remember` a `lessons/` page — trigger, root cause if known,
   what would have caught it earlier — wikilinked to `[[projects/<repo>]]` and the reverted
   change. This is the write-back that makes the next incident shorter.

## Related

`ship` (the forward path; its verification failure is this skill's trigger) · `land` (fix-forward
and re-landing the corrected change) · `store-release` (halting staged store rollouts) ·
`remember` (postmortem capture).
