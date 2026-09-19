# Chat Studio 1.0.30 (31)

## Changes

- Aligned history browsing with the local Studio Web source at `D:/code/hermes-studio`, commit `b6293a11d9d03c71d191ce4227f7db8730506fb8`: source groups, separate pinned entries, independent pagination, import, unarchive, server-side pin/delete, profile-aware batch deletion, and copyable Web hash-route links.
- Kept history detail read-only and independent of the active chat and draft. Added loading, retry, stale-request and profile-switch guards.
- Shared the single/group chat title and conversation drawer. Group titles display participating agent icons; right swipes open conversations and left swipes open the remote group workspace.
- Added read-only group workspace browsing and full-screen file previews using group-specific server endpoints. Permission failures remain visible without falling back to the phone or a single-chat workspace.
- Raised the validated agent-icon limit from 512 KiB to 2 MiB to accept the upstream Hermes image (991343 bytes), retaining unauthenticated icon fetching, redirect rejection and image validation.

## Verification

- Flutter full test suite: 309 passed, 11 environment-dependent tests skipped.
- `flutter analyze --no-pub --fatal-infos`: no issues.
- `python scripts/verify-app-identity.py`: passed.
- Signed Android release APK built successfully. Manifest verified: `ai.chatstudio.app`, versionName `1.0.30`, versionCode `31`, minSdk 24, targetSdk 36.
- Existing signing certificate retained: SHA-256 `51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`.
- No physical-device, newly deployed live-service, iOS build or remote GitHub Actions validation was performed for this release. History uses the shared mobile message renderer, not a byte-for-byte port of every Web-only tool-result presentation.

## Artifact

`dist/chatstudio-1.0.30-android-release.apk`

SHA-256: `881e2ef2e426224ba6f87015fc8980243c36e86785b7502e6acafc0fde4e9a34`.

Checksums: `dist/chatstudio-1.0.30-SHA256SUMS.txt`. Binaries and signing material are not committed.
