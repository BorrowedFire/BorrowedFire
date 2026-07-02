---
name: deps
description: Dependency and security-update loop. Invoked by `maintainer` for dependency-update PRs (Dependabot/Renovate) or explicitly when the user says "/deps", "update dependencies", "handle the dependabot PRs", "security updates", "bump the deps", or "audit vulnerabilities". Batches updates by risk, reads changelogs on majors, and lands each batch through `land`. NOT for general refactors, NOT for adding new dependencies to implement a feature, and NOT a substitute for `land`'s gates — it feeds them.
---

# Deps

Turn dependency noise into a small number of well-batched, well-proven landings. Dependency
updates are ideal autonomous work — bounded, reproducible, with a natural live-proof path (build +
tests + the app actually running) — *if* they're batched sensibly and majors are read, not
YOLO-merged.

## Rules

- **Batch by risk, one ecosystem per branch** (npm / pip / Swift PM / Gradle / Actions …):
  - Batch A — patch + minor, green CI: one branch per ecosystem.
  - Batch B — majors: **one branch each**, only after reading the changelog/release notes for
    breaking changes that touch this repo's usage (grep for the APIs named).
  - Batch C — security advisories: jump the queue; still proven, never blind.
- **Lockfile-only conflicts** are regenerated, never hand-merged.
- A dependency update that requires **code changes** to adapt is no longer a deps item — it
  becomes a normal bounded change (note it, implement the adaptation in the same branch if small,
  or hand to `triage` to shape if not).
- Everything lands through **`land`** — its gates, its denylist, its live proof. Deps never
  merges on its own authority. Live proof for deps = the app/service actually exercising the
  updated path, not just a green install.
- Respect the registry (`projects/<repo>.md`): `autonomy: read-only` repos get a report, not
  branches.
- **Never update past a pin/constraint comment** ("pinned: see issue X") without surfacing it —
  pins exist for reasons; find the reason (`recall` `lessons/`, git blame) before proposing to
  break it.

## Flow

1. **Inventory.** Open Dependabot/Renovate PRs, `npm audit` / ecosystem equivalent, outdated list.
   `recall` `lessons/` for prior dependency gotchas in this repo (there are always some).
2. **Plan batches** per the rules; report the plan in one table (batch · items · risk · proof
   plan).
3. **Execute per batch:** branch → update → regenerate lockfiles → build + tests → the changed
   path exercised live where feasible → hand to `land`. Existing bot PRs: adopt them into batches
   (close superseded ones with a comment linking the batch PR).
4. **Report.** Landed batches (shas), deferred majors with the exact breaking-change concern,
   security items' status, pins encountered. Capture recurring gotchas via `remember` to
   `lessons/`.

## Related

`maintainer` (routes dependency PRs here) · `land` (every batch lands through it) · `triage`
(shapes updates that grew into real changes).
