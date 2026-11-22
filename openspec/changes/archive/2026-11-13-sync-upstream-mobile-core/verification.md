# Implementation and verification log

## 2026-11-13

Implementation and acceptance follow the user-approved scope: real pinned Studio execution driven by a deterministic local model, and local Android emulator checks. Real external models remain unverified. The user explicitly waived iOS; no iOS pass is claimed. These decisions are reflected in proposal, design, tasks and the compatibility delta.

All 63/63 implementation and acceptance tasks are complete within the explicitly approved scope. All final baseline runs passed. Eight main specifications (52 requirements) were synchronized, compared against every delta and passed strict validation before this change was archived as 2026-11-13-sync-upstream-mobile-core.

### Environment and exact baselines

Windows, PowerShell 7.7, Node 24.13.1, Flutter 3.44.9 / Dart 3.12.2. Android 16 / API 36 Google APIs x86_64 emulator, WHPX acceleration, software rendering with Vulkan disabled. Installed Codex CLI 0.154.0 uses an isolated local Responses provider.

| Baseline | Exact commit |
| --- | --- |
| legacy | b44c74318fe5a0a1f3aed29d5095393964fc3d62 |
| stable | 312425cca7d707a115d230f0252e9d55786ec57e |
| preview-agents | 302cf39b7cc77410430694eebfb79dc8aff11b97 |

### Counted verification

| Check | Observed result |
| --- | --- |
| Node manifest/report tests | 4 passed |
| Runner preflight | Correct SHAs accepted; mismatch rejected before startup; occupied port fails without stopping unrelated listener |
| Dart format, lib/test/integration_test | 156 files, zero changes |
| Flutter static analysis | No issues |
| Full Flutter suite, BOT enabled by default | 433 executed, 22 skipped, zero failures/errors |
| Stable final contracts with actual NativeCodex CLI | 18 executed, 2 skipped, zero failures/errors |
| Legacy final contracts | 12 executed, 8 skipped, zero failures/errors |
| Preview final contracts | 17 executed, 3 skipped, zero failures/errors |
| Android native interface/interaction suite | 24 executed, zero skipped/failed |
| Android real Studio BOT lifecycle suite | 3 executed, zero skipped/failed/errors |
| Independent real-storage cache fault matrix | 1 executed, zero skipped/failed |
| Bash syntax | Passed; full Linux lifecycle not run |
| OpenSpec strict validation | Change passed; all 8 synchronized main specs passed |

The 22 Flutter skips are environment-dependent live contracts, counted separately from executed unit/widget/controller tests. Stable's two skips are the preview-only plugin case and legacy-only missing-capability case. Preview skips native Codex (not requested there), the stable-only observer scenario and the legacy-only missing-capability scenario; its controlled plugin executes. Legacy skips the native CLI, stable observer, preview plugin, stable goal cascade, three BOT lifecycle cases and BOT storage-fault case; its explicit missing goals/selection/Person fallback executes. Android device output includes Gradle/install progress; raw output is retained privately, JSON events are extracted and checked by the same strict reporter. Zero, skipped-only, hidden-only, incomplete, error and failed reports cannot pass.

### Implemented behavior and evidence

- Shared pinned manifest drives PowerShell/Bash/CI. Runners isolate server homes, accounts, workspaces, databases and Codex configuration, rotate test credentials, verify authenticated health and clean only owned processes. Suites run serially against the single disposable DB because cache seeding opens a second SQLite connection; two-client concurrency remains explicit inside each applicable suite. A parallel run exposed a real SQLite lock in group persistence; it was not hidden or retried as a successful write.
- Agent metadata covers 16 known IDs, aliases, scoped/native modes, model/API/reasoning metadata, installed state and exact plugin route encoding. Approved authority rule: Ekko/Hermes always use availability, Coding/plugin descriptors use the unified registry; valid empty Coding catalogs never guess installed entries. Temporary failures are distinct from missing routes or resource ACL failures.
- Server/account/Profile/Agent/mode preferences and saved-session continuation preserve actual configuration. Installed Codex executes one global conversation and a second-client continuation through a local Responses provider. Other native Agents have protocol-only coverage. Hermes direct command contracts do not claim Hermes CLI execution because no Hermes runtime is installed.
- Independent read-only observer handles working/unread/removal state with scoped generations. Numeric read ACKs require actually painted assistant content; unseen attention and card-only pages retain unread state. Android exposed a disabled-animation input layout assertion; reduced-motion rendering now omits the animation wrapper and the native suite passes.
- Remote archive/delete/403 handling verifies authoritative details and preserves scoped text/attachment drafts. Older reading windows remain stable until explicitly returning to latest; clear generations reject late pages and do not replay runs.
- Goals use user GET/PATCH routes, exact updated_at preconditions, search/status/order/Profile scope and cancellable bounded evidence lookup. Stable real Ekko goal tools create over 60 history rows and completed evidence. Two clients verify conflicts, source deletion removing goals and evidence deletion reopening goals/clearing evidence. Legacy retains ordinary run plans.
- Single-chat numeric and group opaque-string selection protocols stay separate. Server groups include hidden/cross-page records and protect summary/unknown boundaries. Confirmation/cancellation, conflicts and unknown outcomes never auto-stop or replay deletion. Real group contracts persist 155 records and verify both clients' totals and cross-page deletion. Native long-press text keeps Copy and exposes selection for both user and assistant messages.
- BOT routing precedes ordinary Agent routing. Account ownership, resource ACLs, independent drafts/configuration and private-worker exclusion are enforced. Revoked execution Profile disables new runs while preserving still-authorized account-owned main history. Foreign-account BOT reads return 404; caches cannot cross account scopes.
- Real stable Ekko background execution requests durable clarification, accepts one answer, rejects a second answer with 409, writes a result file through write_file and downloads the exact authorized bytes. Follow-up creates a second execution in the same private conversation; historical execution stays read-only. A stopped main run leaves a separately running background task intact, then an explicit task stop ends it. Disconnect/resume does not duplicate the run.
- Sequential and parallel flows each complete two finite rounds using actual bot_flows_query/bot_flow_control tools, live stage/run preconditions and persisted final results. Repeated create uses the same key/flow, both clients see matching completed revisions, and completed flows reject resume. Separate actual stop/resume and stale-revision conflict contracts pass.
- BOT timeline uses person-display-v1 mixed typed references and opaque cursors. Unit/controller tests cover card-only pages, overlapping IDs, stale revisions, hidden detail pages, independent history_key, unknown projection, bounded/cancellable result lookup and atomic interrupted/corrupt caches. The real-storage fault matrix persists 450 mixed references, keeps at most 300 in cache, preserves the exact latest cache ID, recovers missing cache hits, restores offline windows, handles other-client clear/permission changes and rejects late pre-clear content while retaining drafts.
- Android UI checks cover Agent/mode/model selection, English unavailable reasons and language preference, unread/painted ACK behavior, single/group typed selection and confirmation, BOT list/search/switch boundaries, durable interaction, authorized/expired attachments, finite collaboration validation, older history/clear recovery, task filters and exact evidence navigation without a run. Validation errors surface at the action as a visible snackbar. Native network tests additionally run the full three BOT lifecycle contracts against real stable Studio through an owned reverse port.
- Full BOT and preview plugin entry points are enabled only after their respective gates. STUDIO_PLUGIN_AGENTS=false, STUDIO_SESSION_TASKS=false, STUDIO_MESSAGE_SELECTION=false and STUDIO_BOTS=false independently close the new entries. Closing an entry does not stop or mutate remote work.

### Delivery and limits

README translations, Agent/runtime guides, goal/deletion effects, BOT prerequisites/history/cache/rollback, compatibility matrix, privacy and unreleased notes describe the final behavior. Original upstream attribution and THIRD_PARTY_NOTICES are preserved. Pre-existing structured-interaction changes were retained.

Real external models, iOS, full Linux service lifecycle and CI dispatch are unverified. WSL has no Linux distribution and Git Bash lacks setsid; Bash syntax/preflight are not claimed as Linux execution. The local model validates client/server execution and persistence, not model quality. No commit, push, release or production deployment is implied.

Private logs, credentials, databases, test-defined APKs and raw reports stay under ignored .local/ or build output and must not be published. The separately rebuilt normal debug APK targets lib/main.dart with no test credentials.
