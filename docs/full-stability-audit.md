# AIQuickNote Full Audit Report

## 1. Baseline

Audit started 2026-10-03 on `main` at `3147bfd0b125e79298f2533e00a684868c930170`. Ending implementation commit: `d454ef7f3b1d24012f8246e904421c00a6c476c6`; branch: `main`. The final handoff commit contains documentation only (see commit sequence). Current phase remains Fireseed Identity Phase 3D. The two untracked user files are excluded from all changes.

## 2. Audit scope

Inspected: current handoff, Identity design/Phase 3B/3C notes, README, release rules; SwiftUI lifecycle/navigation/composer/detail/search/settings/skins/speech/sharing; AppModel, IdentityKit and pinned Logto adapter; Swift JSON store/Core/ownership/search/archive; Python SQLite Core/MCP contracts and schemas; all three iOS workflows, project targets, scheme, Info.plist and ExportOptions.

Existing tests: 6 Python contract tests; 29 Swift package tests; 38 app-hosted unit tests; 4 UI interaction tests. The baseline Windows Python suite passed. Existing ordinary iOS CI run `37132712003` failed at `testAllHomeCardsOpenAndDetailFloats` (detail.close did not appear); Core and app unit suites passed. Post-repair evidence is recorded in sections 8 and 9.

## 3. Problems found

The A01-A13 list was recorded before code changes; later findings are identified separately below.

| ID | Priority | Problem / root cause / impact | Planned minimal fix |
| --- | --- | --- | --- |
| A01 | P0 | Python records have no owner column. Any separately authorized subject can read another subject's records. Reproduced through MCP public calls. | Add subject ownership, owner-scoped get/search/replay; preserve legacy unowned rows without claiming them. |
| A02 | P0 | Identity restore assigns state after an await without checking whether logout or newer login invalidated it. Late restore can resurrect a signed-out identity. | Invalidate stale state transitions and serialize provider operations; regression tests with controlled continuations. |
| A03 | P1 | Cancel immediately releases the login task slot; old SDK work can finish while a newer login or logout runs. | Keep the operation busy until completion, reject stale callbacks, clear failed/cancelled SDK credentials. |
| A04 | P1 | AppModel does not forward nested IdentityKit changes; restore is one-shot and failed reload retains previous records. | Publish lifecycle activity, forward identity notifications, clear cached records on load failure. |
| A05 | P1 | Detail reparsing replaces reminder linkage and can request a second system reminder; input parse results can overwrite later edits. | Preserve operational fields and reject cancelled/stale parse results. |
| A06 | P1 | Search lower/upper amount bounds may match different items, accepting records with no amount in range. | Apply both bounds to the same amount item; regression test. |
| A07 | P1 | SQLite transaction lock is not released if BEGIN/COMMIT fails; malformed MCP inputs and typed fields can escape validation. | Exception-safe transaction cleanup, validate payloads and schema field types. |
| A08 | P1 | Swift archive restore accepts duplicate IDs; archive decoder accepts duplicate entry names and can force-unwrap empty inflate buffers. | Reject duplicate record/entry IDs and make decompression buffer access safe. |
| A09 | P1 | Root login sheet competes with module composer/settings sheets; first-save path from a module needs UI coverage. | Present login from the active review/settings context and add module-first-save regression coverage. |
| A10 | P2 | Login has no busy state; pagination icon controls and important toggle lack adequate labels/touch targets. | Add progress/disabled state and accessibility labels with system controls. |
| A11 | P2 | Skin and share errors are silently discarded; media selection currently does not attach anything. | Surface failures and clearly identify unavailable attachment persistence; do not implement a new attachment feature. |
| A12 | P3 | Release rules ask for committed build-number changes although archive overrides version/build; ordinary CI lacks Release validation and Python checks. | Align docs with dispatch inputs and add ordinary CI checks without uploading. |
| A13 | P3 | Existing cancellation test has no cancellation assertion and tests use timing yields instead of controlled suspended providers. | Add meaningful lifecycle race tests; retain existing assertions. |

Follow-up findings during repair (P1, each fixed): amount editing accepted numeric prefixes instead of the complete input, risking silently incorrect amounts; full-string decimal validation now respects the locale decimal separator and rejects malformed input. Stale detail/share screens could retain another account's records; saves and shares now recheck current ownership. Other follow-up findings: speech installed an audio tap before activating/validating the input format (P1); the local OIDC harness logged full authorization URLs and used socket idle timeout instead of a whole-run deadline (P1). These were corrected with format validation, a loopback launcher, safe diagnostic text and a real deadline. New local harness tests verify PKCE/signatures and invalid-state rejection using disposable local fixtures, not real credentials.

Release review: formal Bundle ID, URL scheme, orientations, AppIcon and app-only provisioning setting are present; Production identity defaults are empty and STAGING values are command-line archive overrides. No TestFlight run is authorized by this audit. Real iPhone OTP/browser/session behavior remains a manual acceptance gate.

## 4. Code changes and outcomes

- A01: subject column and get/search/idempotency ownership checks added; no legacy row is claimed or deleted. Two authorized subjects cannot see each other's records. Invalid grant-key separator inputs are rejected to prevent aliasing.
- A02–A04: restore results are revision-checked; logout invalidates old state immediately and waits for outstanding provider operations. Cancellation disarms the save and keeps the provider slot occupied until it settles. Nested identity notifications reach AppModel. Failed disk reload clears the visible cache. Stale detail saves cannot move data into a different account.
- A05: parsed detail content preserves ID, issuer/owner, timestamps, importance and reminder linkage; stale/cancelled parse results are discarded. Initial review no longer reparses a manually chosen module. Leaving review invalidates only that draft's pending continuation.
- A06: both numeric bounds apply to one amount item.
- A07: transaction locks release on failure; malformed transport calls, modules, amounts, currencies, dates and non-finite JSON fail validation.
- A08: duplicate record IDs and archive entry names fail before restore; foreign-ID collisions are rejected. Archive expansion is limited to 50 MB / 1,000 entries and empty buffers no longer cause force-unwrap crashes.
- A09: login for a first save is presented by the active review, including module composer sheets. Settings waits for dismissal before requesting the root login sheet.
- A10–A11: authentication activity has visible progress and a disabled login button; pagination and importance controls have labels; pagination has 44-point targets; card height scales with text size and falling skins respect Reduce Motion. Skin/share failures are surfaced. Selecting a photo now explicitly reports that attachment persistence is not implemented; no new attachment storage was added. Share generation checks current ownership.
- A12–A13: ordinary CI now runs Python contracts, local OIDC harness tests, Swift package tests, Release build/compiled Production metadata checks, Debug build, app unit and UI tests. Xcode tests run serially to reduce concurrent simulator contention seen in baseline logs. Release instructions now match archive-only dispatch overrides. Existing test assertions are retained.

## 5. UI/UX changes

Floating Composer, tilt/reflection cards, Bottom Sheet and skins are retained. No product redesign or new feature was introduced. The original detail-navigation regression and all five UI tests passed in the final macOS run. This is simulator interaction acceptance, not a complete physical-device visual matrix.

## 6. Identity Phase 3D findings

The real provider remains pinned to Logto Swift SDK `2.0.0-beta.1`. Its browser auth path owns state/PKCE, token verification and callback handling. The app now requires exact callback/logout URIs, a nonempty HTTPS authority for STAGING/PRODUCTION and issuer-qualified identity mapping; email remains an attribute. Failed/cancelled sign-in clears SDK credentials. Network, cancellation and authentication failure have separate outcomes. No token, OTP, auth code or PKCE verifier was read or logged during this audit.

Production identity defaults and the manual TestFlight workflow are unchanged. Signing/profile scope, Bundle ID, orientations and AppIcon are checked; ordinary CI never uploads an IPA. Identity, Backup, Sync and Share remain separate; existing archive code received validation fixes only.

## 7. Tests added

- Python: cross-subject get/search/reopen and replay isolation; legacy migration without adoption; malformed input; grant-key alias prevention; failed-transaction lock release; malformed transport; release/URL/orientation/icon/profile constraints.
- Swift Core: same-item amount ranges; reparse metadata; disk relaunch/corruption preservation; duplicate restore/foreign-ID rejection; duplicate archive names; complete locale-aware amount validation.
- App-hosted: controlled suspended provider tests for late restore after logout, cancellation and late login callback, no concurrent login, exactly-once first save, same-account relogin, relaunch restore, failed restore, exact redirect validation, leaving review and stale detail ownership.
- UI: first save and cancellation through a module composer sheet, alongside all four existing navigation/search/first-save regressions.
- Node: local mock OIDC issuer signs disposable test claims; valid PKCE/ES384 path passes and invalid state is rejected without logging the authorization URL.

## 8. Tests executed

Windows: 15 Python tests passed; 2 Node harness tests passed; Node syntax check and Git whitespace checks passed. Python uses the existing bundled runtime; no dependency installation was needed. Windows did not execute Swift/Xcode tests.

GitHub macOS at `d454ef7f3b1d24012f8246e904421c00a6c476c6`: 35 Swift package tests, 51 app-hosted unit tests (38 existing Core + 7 IdentityRace + 6 Stability), and 5 UI tests passed with zero failures. Release simulator build, compiled Production identity metadata checks, Debug simulator build, 15 Python tests and 2 local OIDC harness tests also passed. Package and app tests share some test source; these counts are executions in separate targets, not unique test cases.

## 9. CI result

| Run | Commit | Result / evidence |
| --- | --- | --- |
| `37132712003` | `3147bfd` | Baseline failure: detail navigation UI; package/app unit tests passed. |
| `37151290414` | `408db4e` | Failed new module-first-save UI regression; initial Review reparsing changed selected module. Fixed without weakening assertions. |
| `37151504505` | `7f682a6` | Passed: review lifecycle fix and all five UI tests. |
| `37151631091` | `dcc9dfb` | Passed: stale account write regression included. |
| [37152279415](https://github.com/flysnoww/ai-shouji/actions/runs/37152279415) | `d454ef7` | **SUCCESS**: final implementation, all stages complete; job `111288436130`. |

Audit validation runs are ordinary iOS CI, never TestFlight upload. The final documentation-only push may trigger another ordinary run; the readiness gate above is based on the completed run for the identical implementation, not an assumed result for that later run.

## 10. Remaining risks

- Execute all four real-iPhone Phase 3D tests in CURRENT_STATUS.md against the intended live Logto issuer. Automated deferred providers and local mock OIDC do not prove a live email/ASWebAuthenticationSession/Keychain round trip.
- The SDK browser operation may need the system browser's Cancel action to settle after task cancellation; new operations are safely blocked until it does. Verify this on the physical phone.
- Verify physical EventKit permission, reminder reconciliation and microphone interruptions, plus VoiceOver/Reduce Motion, large Dynamic Type, small/large iPhone and iPad landscape, light/dark and imported skins. Simulator/static checks do not establish all visual combinations.
- P3 compiler debt remains: Swift 6 actor-isolation warnings at the synchronous `IdentityGate` boundary, the `Date.init` Sendable conversion, deprecated SwiftUI callbacks/interpolation and unused test return values. Current app Core calls run on the main actor; upgrading language mode or moving Core access off that actor needs a separate concurrency contract review. Tests pass under the existing project settings, not Swift 6 strict mode. SDK/test-binary metadata/stripping warnings also appear in Xcode logs.
- JSON persistence rewrites the local dataset synchronously; performance with large user datasets and memory pressure is unmeasured. No broad storage rewrite was introduced.
- Python ACI and native Swift are separate existing implementations; this audit aligns ownership safety but does not claim a shared runtime or production remote adapter.
- Attachment persistence remains unavailable and is disclosed in the UI. Production credentials remain unconfigured; temporary STAGING tunnels can expire.

## 11. Manual real-device tests still required

1. Signed out -> Draft -> Save -> real Logto Email OTP -> callback -> PendingSave consumed once -> exactly one record.
2. Logout -> private records hidden -> same-account login -> same issuer/sub -> previous record visible, no duplicate.
3. Force quit -> relaunch -> session restored -> same canonical identity -> previous record available.
4. Cancel authentication -> no write, Draft retained -> later unrelated login must not consume the cancelled PendingSave.

Use the STAGING configuration in [CURRENT_STATUS.md](../CURRENT_STATUS.md). Verify temporary endpoint availability before a separately authorized Build 6 upload. This audit did not upload or install a new TestFlight build.

## 12. Current project status

Fireseed Identity Phase 3D remains current. `IOS_TESTFLIGHT_PIPELINE_PASSED` is the accepted prior release milestone. **`READY_FOR_IDENTITY_3D_REAL_DEVICE_TEST`**: code and ordinary CI passed. Real-device acceptance is not claimed. `IDENTITY_3D_REAL_DEVICE_PASSED` requires the user's four physical-iPhone passes. No identified P0/P1 audit fix remains unvalidated by its available regression coverage; physical device and compiler/performance limitations remain as listed above.


## Changed files and commit sequence

Implementation and tests: `quicknote_aci/core.py`, `quicknote_aci/mcp_adapter.py`, `ios/QuickNoteCore/Core.swift`, `ios/AIQuickNote/AIQuickNoteApp.swift`, `ios/AIQuickNote/FireseedIdentityKit.swift`, `ios/AIQuickNote/LogtoIdentityProvider.swift`, `ios/AIQuickNote/Localizable.xcstrings`, `ios/QuickNoteCoreTests/CoreTests.swift`, `ios/AIQuickNoteUITests/NavigationRegressionTests.swift`, `tests/test_stability.py`, `tests/test_release_configuration.py`, `tests/identity/oidc-pkce-smoke.mjs`, `tests/identity/oidc-pkce-smoke.test.mjs`.

CI and documentation: `.github/workflows/ios-ci.yml`, `docs/testflight-release.md`, `docs/full-stability-audit.md`, `CURRENT_STATUS.md`, `README.md`, `TEST-RESULTS.md`.

| Commit | Scope |
| --- | --- |
| `3aa97ad` | Reference ownership and validated writes |
| `bf68b4d` | Identity lifecycle, persistence, UI state and regressions |
| `408db4e` | Release checks, ordinary CI and initial issue record |
| `7f682a6` | Review lifecycle, archive/audio guards and local OIDC harness |
| `dcc9dfb` | Stale detail ownership and share checks |
| `d454ef7` | Complete locale-aware amount input |

The final documentation-only commit can be located with `git log -1 -- docs/full-stability-audit.md`; it does not change the tested implementation. No secrets, provisioning material, production identity configuration or TestFlight workflow were modified. The two protected untracked files remain excluded.
