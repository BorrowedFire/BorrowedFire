---
name: takeoff
description: One-command closeout for committing, pushing, merging, deploying, and verifying. Use when the user says "/takeoff", "takeoff", "ship it", "commit merge deploy", "merge and deploy", or "push this live".
---

# Takeoff

Close out the current work end to end: commit exact changes, push, merge when checks pass, deploy through the repo-native path, and verify production.

## Rules

- Work from fresh repo and live-system evidence.
- Stage exact files only. Never use `git add .` or `git add -A`.
- Never reset, force-push, or discard user changes.
- Never merge with failing checks.
- Never deploy if the production target or credentials are ambiguous.
- If deploy intent is clear and the target is obvious, proceed without another confirmation.
- If the request mentions App Store, TestFlight, Play Store, AAB, IPA, store submission, mobile release tags, or binary version/build bumps, hand off to `/orbit`.

## Flow

1. Gather state: `git status --short`, diff/stat, branch, default branch, recent commits, open PR, deploy docs/configs.
2. Run focused tests first; run broader gates when risk or repo policy warrants it.
3. If on default branch or detached HEAD, create a `codex/<short-slug>` branch.
4. Commit logical file groups with repo-style messages.
5. Push branch and create/update PR with tests and deploy plan.
6. Wait for required checks; merge using repo convention, defaulting to squash.
7. Deploy from the canonical source, usually updated default branch.
8. Verify production with real evidence: live route, SQL/RPC, logs, workflow, store status, or function response.
9. Final report: commit(s), PR/merge, deploy target, verification evidence, and any residual blocker.

## Deploy Detection

- Supabase: apply migrations, deploy changed Edge Functions, run required sync/backfill, query invariants.
- Netlify/Vercel/Cloudflare: use repo-native production command or workflow and verify live URL.
- GitHub Actions: trigger/monitor documented release workflow.
- iOS/Android store releases: use `/orbit`; `/takeoff` only handles normal code closeout before the store train.
