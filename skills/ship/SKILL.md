---
name: ship
description: Close out authorized work through commit, push, merge, deployment, and verification. Use for shipping changes. Mobile store builds use store-release.
---

# Ship

Close out the current work end to end: commit exact changes, push, merge when checks pass, deploy
through the repo-native path, and verify production.

## Rules

- Work from fresh repo and live-system evidence.
- Stage exact files only. Never use `git add .` or `git add -A`.
- Never reset, force-push, or discard user changes.
- Never merge with failing checks.
- Never deploy if the production target or credentials are ambiguous.
- If deploy intent is clear and the target is obvious, proceed without another confirmation.
- Preserve the repository's existing review and owner gates. For non-trivial logic, an unfamiliar
  area, an owner-requested review, or a required repository review loop, hand the merge step to
  `land`. A shipping request does not waive that review. Resume the authorized deployment after merge.
- Match each stage to the request and prior grants. A request to commit or push does not itself
  authorize merge or deployment. Complete routine reversible preparation within the granted scope.
- If the request mentions App Store, TestFlight, Play Store, AAB, IPA, store submission, mobile
  release tags, or binary version/build bumps, hand off to `store-release`.

## Tool adapters

| Abstract step | Claude Code | Codex | Other harnesses |
|---|---|---|---|
| branch prefix (step 3) | `claude/<short-slug>` | `codex/<short-slug>` | `<harness>/<short-slug>` |
| review-loop handoff | `/land` | `$land` | the `land` skill |

## Flow

1. Gather state: `git status --short`, diff/stat, branch, default branch, recent commits, open PR,
   deploy docs/configs. If a brain is available, `recall` the repo's `lessons/` first.
2. Run focused tests first; run broader gates when risk or repo policy warrants it.
3. If on default branch or detached HEAD, create a branch (prefix per Tool adapters).
4. Commit logical file groups with repo-style messages.
5. Scan the exact outgoing content for secrets before publication. Push the branch and
   create/update the PR within the authorized scope, with tests and any requested deploy plan.
6. Satisfy all required reviews, proof, checks, and owner gates for the current candidate.
   Merge only when authorized, using repo convention, defaulting to squash.
7. If deployment is authorized, verify the intended commit and target immediately before
   deploying from the canonical source, usually updated default branch.
8. Verify production with real evidence: live route, SQL/RPC, logs, workflow, store status, or
   function response.
9. **If verification fails:** stop — do not stack further deploys on a broken state. Report what
   was observed, and propose the exact `rollback` action (revert sha / previous deploy target).
   Never leave a failed deploy unreported.
10. Final report: commit(s), PR/merge, deploy target, verification evidence, and any residual
    blocker. Capture any new deploy gotcha via `remember` to `lessons/`.

## Deploy Detection

- Supabase: apply migrations, deploy changed Edge Functions, run required sync/backfill, query
  invariants.
- Vercel/Cloudflare: use repo-native production command or workflow and verify live URL.
- GitHub Actions: trigger/monitor documented release workflow.
- iOS/Android store releases: use `store-release`; `ship` only handles normal code closeout before
  the store train.
- Unknown platform: stop and ask — never guess a production path.
