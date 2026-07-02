---
name: orbit
description: Store-release closeout for App Store and Play Store. Use when the user says "/orbit", "orbit", "send to App Store", "submit to TestFlight", "release to Play Store", "create the store release", "tag the iOS release", "tag the Android release", "bump to the next build", or asks to create GitHub releases for mobile store builds.
---

# Orbit

Ship mobile binaries and release metadata. Use this for App Store / TestFlight / Play Store release trains, not ordinary backend/web deploys.

## Rules

- Verify live store state first; repo docs are not enough.
- Never reuse a live or closed store version/build.
- Update repo metadata, GitHub Release metadata, and release docs together.
- Create tags only after the commit that contains the exact version/build metadata is pushed.
- After a store release is accepted/live, move the repo to the next intended version/build when requested or when repo convention expects it.

## Flow

1. Identify scope: iOS, Android, or both.
2. Verify current store state:
   - iOS: App Store Connect version/build, processing state, submission state.
   - Android: Play Console track assignment, `versionName`, `versionCode`, release status.
3. Pick the next valid train:
   - iOS: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `ios/project.yml`, then regenerate Xcode.
   - Android: bump Gradle `versionName` / `versionCode`, store notes, and release docs.
4. Run release-grade checks: build/test/archive/export or repo release workflow dry-run as appropriate.
5. Commit exact files, push, PR/merge through normal checks.
6. Tag the merged release commit:
   - iOS: `ios/v<version>-build<build>`
   - Android: `android/v<versionName>-build<versionCode>`
7. Create/update the GitHub Release with version, build/code, platform, track, commit, artifact/workflow links, and store status.
8. Upload/submit or trigger the repo-native release workflow.
9. Verify processing/submission/live state in the store.
10. Record final state in `docs/releases/` and report evidence.

## Handoff

If normal deploy work is still unmerged, run `/takeoff` first. If `/takeoff` detects App Store, TestFlight, Play Store, AAB, IPA, mobile release tag, or binary submission intent, it should hand off here.
