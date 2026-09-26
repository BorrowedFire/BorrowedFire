---
name: store-release
description: Prepare or execute requested mobile release stages, including version bumps, builds, uploads, and store submission. Preserve owner submission and rollout gates.
---

# Store Release

Ship mobile binaries and release metadata. Use this for App Store / TestFlight / Play Store
release trains, not ordinary backend/web deploys. Store submission is the most irreversible action
in the system — it is **owner-gated by default**.

## Rules

- Verify live store state first; repo docs are not enough.
- **How to verify store state:** use the repo-native tooling in this order — a documented fastlane
  lane, the App Store Connect / Play Developer API with configured credentials, or the repo's
  release workflow logs. If none is available, **ask the owner for the current store state**
  (version/build, processing/submission status) before proceeding — never infer it from the repo.
- **Owner gate:** actually *submitting* for store review (or promoting a track/rollout) requires
  explicit owner confirmation in this run, unless the invocation pre-authorized it ("submit
  without asking"). Execute only the release stages the request authorizes. A version or build
  bump does not authorize a binary upload, tag publication, GitHub Release, or store submission.
- Carry prior grants forward. Complete all authorized preparation before asking at a remaining
  gate. The sequence below is conditional on the selected stages, not permission for every stage.
- Never reuse a live or closed store version/build.
- Keep metadata consistent across the release surfaces included in the authorized stages.
- Create tags only after the commit that contains the exact version/build metadata is pushed.
- Prefer staged rollout where the store supports it (phased release on iOS, staged rollout
  percentage on Play); know the halt mechanism before you submit — halting a bad rollout is the
  store-world `rollback`.
- After a store release is accepted/live, move the repo to the next intended version/build when
  requested or when repo convention expects it.

## Flow

1. Identify platform and stages: metadata bump, build/archive, upload, tag, GitHub Release, store
   submission, or rollout. Use the user's request and prior grants. If a brain is available,
   `recall` the project's registry page and `lessons/` for prior release gotchas.
2. Verify current store state (per the rule above):
   - iOS: App Store Connect version/build, processing state, submission state.
   - Android: Play Console track assignment, `versionName`, `versionCode`, release status.
3. Detect the project's version convention — do not assume one:
   - XcodeGen (`project.yml` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, then regenerate),
     raw `.xcodeproj` build settings, or a fastlane versioning lane — whichever the repo uses.
   - Android: Gradle `versionName` / `versionCode`, store notes, and release docs.
4. If a metadata bump is requested, apply the requested valid version/build through the detected
   convention. Otherwise verify that the existing metadata matches the selected release artifact.
5. Run checks required for the selected stages. A metadata-only change needs metadata validation
   and required repository checks; it does not require an upload or production release workflow.
6. If repository publication is authorized, commit exact files and push through the normal PR,
   review, proof, and merge gates. A metadata-only request may end with validated local changes.
7. When tag publication is authorized, tag the merged release commit:
   - iOS: `ios/v<version>-build<build>`
   - Android: `android/v<versionName>-build<versionCode>`
8. When GitHub Release publication is authorized, create/update it with version, build/code, platform, track, commit,
   artifact/workflow links, and store status. (Release notes content: `changelog`, with `signal`
   for promotional tone.)
9. When upload or submission is authorized, use the repo-native path. Satisfy the **owner gate**
   before store submission or rollout promotion. Inspect a workflow's effects before triggering it.
10. Verify the processing, submission, or live state for the stages that ran.
11. Report the stages completed and their evidence. Update `docs/releases/` when the requested
    release or repository convention needs that record. Capture durable release gotchas via
    `remember` to `lessons/`.

## Handoff

If normal deploy work is still unmerged, run `ship` first. If `ship` detects App Store,
TestFlight, Play Store, AAB, IPA, mobile release tag, or binary submission intent, it hands off
here.
