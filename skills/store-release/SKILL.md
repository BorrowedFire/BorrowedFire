---
name: store-release
description: Store-release closeout for App Store and Play Store. Use when the user says "/store-release", "store release", "orbit", "send to App Store", "submit to TestFlight", "release to Play Store", "create the store release", "tag the iOS release", "tag the Android release", "bump to the next build", or asks to create GitHub releases for mobile store builds. NOT for ordinary backend/web deploys (`ship`) and NOT for landing unmerged code (`land`).
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
  without asking"). Everything before submission (bump, build, tag, GitHub Release) is autonomous.
- Never reuse a live or closed store version/build.
- Update repo metadata, GitHub Release metadata, and release docs together.
- Create tags only after the commit that contains the exact version/build metadata is pushed.
- Prefer staged rollout where the store supports it (phased release on iOS, staged rollout
  percentage on Play); know the halt mechanism before you submit — halting a bad rollout is the
  store-world `rollback`.
- After a store release is accepted/live, move the repo to the next intended version/build when
  requested or when repo convention expects it.

## Flow

1. Identify scope: iOS, Android, or both. If a brain is available, `recall` the project's registry
   page and `lessons/` for prior release gotchas.
2. Verify current store state (per the rule above):
   - iOS: App Store Connect version/build, processing state, submission state.
   - Android: Play Console track assignment, `versionName`, `versionCode`, release status.
3. Detect the project's version convention — do not assume one:
   - XcodeGen (`project.yml` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, then regenerate),
     raw `.xcodeproj` build settings, or a fastlane versioning lane — whichever the repo uses.
   - Android: Gradle `versionName` / `versionCode`, store notes, and release docs.
4. Pick the next valid train and bump through the detected convention.
5. Run release-grade checks: build/test/archive/export or repo release workflow dry-run as
   appropriate.
6. Commit exact files, push, PR/merge through normal checks (hand to `land` if the diff warrants a
   review loop).
7. Tag the merged release commit:
   - iOS: `ios/v<version>-build<build>`
   - Android: `android/v<versionName>-build<versionCode>`
8. Create/update the GitHub Release with version, build/code, platform, track, commit,
   artifact/workflow links, and store status. (Release notes content: `changelog`, with `signal`
   for promotional tone.)
9. **Owner gate**, then upload/submit or trigger the repo-native release workflow.
10. Verify processing/submission/live state in the store.
11. Record final state in `docs/releases/` and report evidence. Capture release gotchas via
    `remember` to `lessons/`.

## Handoff

If normal deploy work is still unmerged, run `ship` first. If `ship` detects App Store,
TestFlight, Play Store, AAB, IPA, mobile release tag, or binary submission intent, it hands off
here.
