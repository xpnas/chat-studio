# Pinned Studio compatibility

The source of truth is `tools/studio-baselines.json`. Both runners reject a mismatched checkout before starting a service, and CI derives its matrix from the same manifest. Checks use isolated state, credentials, workspaces and fixed loopback ports. Never run these destructive contracts against a production server/database.

| Baseline | Exact commit | Purpose |
| --- | --- | --- |
| legacy | `b44c74318fe5a0a1f3aed29d5095393964fc3d62` | Existing mobile routes and explicit missing-capability fallback |
| stable | `312425cca7d707a115d230f0252e9d55786ec57e` | Core modes/sync/goals/deletion and BOT protocol contracts |
| preview-agents | `302cf39b7cc77410430694eebfb79dc8aff11b97` | Independent plugin-host enhancement contract |

The server project is [Ekko Studio](https://github.com/EKKOLearnAI/ekko-studio), formerly Hermes Studio. Existing attribution and license notices remain in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Run on Windows:

```powershell
./scripts/studio-contract.ps1 -StudioPath /path/to/pinned-studio -Baseline stable -NativeCodex
```

On Linux:

```sh
bash scripts/studio-contract.sh /path/to/pinned-studio stable
```

`-NativeCodex` (or `CHATSTUDIO_TEST_NATIVE_CODEX=1` for Bash) requires an installed CLI and creates an isolated Codex home with a local Responses provider. This executes the CLI but does not validate a vendor model or every native Agent. Native discovery's other Agents have fixed protocol coverage only. The preview runner installs the repository's minimal controlled plugin into disposable state; plugin management is not added to the mobile product.

Reports count actual executed/skipped/failed/error events and reject zero execution or hidden failures. A skipped live/media/native test is not counted as executed. Suites share one disposable DB and run serially because the cache fault fixture opens a second SQLite connection; dual-client concurrency is exercised inside each applicable suite. Android build progress is retained separately before strict JSON event validation.

On 2026-11-13: Flutter 3.44.9 / Dart 3.12.2, Node 24.13.1, PowerShell 7.7. Formatting and static analysis passed. The Flutter suite executed 433 tests, skipped 22 live/environment-dependent tests, and had zero failures. Android 16 / API 36 x86_64 emulator executed 24 interface/interaction checks and three real-server BOT lifecycle contracts, with zero skips/failures. Final contracts: legacy 12 executed / 8 skipped, stable with native Codex 18 / 2, preview 17 / 3; all had zero failures/errors. Skipped cases and acceptance details are recorded in the [verification log](../openspec/changes/archive/2026-11-13-sync-upstream-mobile-core/verification.md).

The user approved controlled local model acceptance and waived iOS on 2026-11-13. Real external-model BOT behavior and iOS remain unverified. The actual Studio runtime executed clarification, file creation/download, follow-up, isolated stops, sequential/parallel flows with two finite rounds, persisted completed results and cross-client history. Protocol-only fixtures are reported separately. Full BOT is enabled after joint conversation/history acceptance and can be independently disabled.

For Android live contracts, start a local emulator and use `-AndroidDevice emulator-5554` with the stable PowerShell runner; `adb` must be on PATH. The runner forwards its loopback test port and stores disposable compile-time test credentials only in ignored private diagnostics/debug build output. Do not publish that test APK or raw logs. UI rendering checks run with `flutter test integration_test/mobile_sync_acceptance_test.dart -d emulator-5554 --dart-define=STUDIO_BOTS=true`.

The complete Linux service lifecycle and CI dispatch were not executed in this Windows session: WSL has no distribution and Git Bash lacks `setsid`. Bash syntax/preflight checks are separate from execution. Other native Agents remain protocol-only; no external model or iOS result is inferred from Android/CLI success.

Runtime capabilities fail separately: missing goals/selection/Person routes have explicit unavailable entries while ordinary chat and run plans remain usable. Resource 404, route absence, denied access and transient failures are distinguished. Reconnect never probes support with writes.

Rollback switches: `STUDIO_PLUGIN_AGENTS=false`, `STUDIO_SESSION_TASKS=false`, `STUDIO_MESSAGE_SELECTION=false`, `STUDIO_BOTS=false`. Core scoped/global configuration and the read-only observer can also be reverted by shipping the previous client; saved server sessions retain their Agent/model identity, and rollback does not stop or mutate server work. Preview failure does not prove stable failure, but a release with plugin enhancement enabled must pass the preview contract or ship that switch disabled.
