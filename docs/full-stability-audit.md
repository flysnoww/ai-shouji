# AIQuickNote Full Audit Report

## Baseline and audit map

Audit started 2026-10-03 on `main` at `3147bfd0b125e79298f2533e00a684868c930170`. Current phase remains Fireseed Identity Phase 3D. The two untracked user files are excluded from all changes.

Inspected: current handoff, Identity design/Phase 3B/3C notes, README, release rules; SwiftUI lifecycle/navigation/composer/detail/search/settings/skins/speech/sharing; AppModel, IdentityKit and pinned Logto adapter; Swift JSON store/Core/ownership/search/archive; Python SQLite Core/MCP contracts and schemas; all three iOS workflows, project targets, scheme, Info.plist and ExportOptions.

Existing tests: 6 Python contract tests; 29 Swift package tests; 38 app-hosted unit tests; 4 UI interaction tests. The baseline Windows Python suite passed. Existing ordinary iOS CI run `37132712003` failed at `testAllHomeCardsOpenAndDetailFloats` (detail.close did not appear); Core and app unit suites passed. CI evidence must be renewed after repairs.

## Prioritized issue list (recorded before code changes)

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

Release review: formal Bundle ID, URL scheme, orientations, AppIcon and app-only provisioning setting are present; Production identity defaults are empty and STAGING values are command-line archive overrides. No TestFlight run is authorized by this audit. Real iPhone OTP/browser/session behavior remains a manual acceptance gate.

## Execution and final evidence

In progress. This report will be completed with fixes, tests, exact CI run and remaining risks. Do not infer real-device acceptance from automated tests.
