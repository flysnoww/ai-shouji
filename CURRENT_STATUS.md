# AIQuickNote Current Status and Handoff

Last confirmed: 2026-10-03
Release configuration baseline: `81ef749e054c7b5c23383d474240bcc1d821c54f`. Stability audit implementation: `d454ef7f3b1d24012f8246e904421c00a6c476c6` on `main` (see validation gate below).

This is the canonical project handoff for a new machine, Codex task, or chat window. Detailed historical design and implementation notes remain in the linked documents below.

## Current phase

**Fireseed Identity Phase 3D — real iPhone + real Logto Email OTP end-to-end validation.** Identity Phases 3B and 3C are complete and are not the current development phase.

The iOS and TestFlight release pipeline is complete and passed: `IOS_TESTFLIGHT_PIPELINE_PASSED`.

## Stability audit handoff

The full stability audit repaired ownership isolation, Identity lifecycle races, PendingSave/review cancellation, stale account writes, persistence validation, numeric input, error feedback and ordinary CI coverage. See [AIQuickNote Full Audit Report](docs/full-stability-audit.md) for findings, commits, tests and remaining risks.

**Audit gate: `READY_FOR_IDENTITY_3D_REAL_DEVICE_TEST`.** Ordinary iOS CI [run 37152279415](https://github.com/flysnoww/ai-shouji/actions/runs/37152279415) passed at implementation commit `d454ef7f3b1d24012f8246e904421c00a6c476c6`: 35 Swift package, 51 app unit and 5 UI tests; Release/Debug builds; Production metadata checks; 15 Python and 2 local OIDC harness tests. A later documentation-only commit does not change that tested implementation. No new TestFlight build was uploaded during this audit. The four physical-iPhone acceptance tests below remain pending; do not mark them passed from simulator or mock-provider evidence.

## iOS and TestFlight release status

- Production Bundle ID: `org.tmiai.aiquicknote`.
- Workflow: `.github/workflows/ios-testflight.yml`.
- The GitHub Actions → Apple Distribution signing → archive → signed IPA export → App Store Connect → TestFlight path has run successfully.
- TestFlight Marketing version `0.1`, Build `5` uploaded successfully and was installed and opened on a physical iPhone through TestFlight.
- Completed release engineering: Apple Distribution certificate, App Store provisioning profile, App Store Connect Team API key, GitHub Repository Secrets, signed archive, signed IPA export, TestFlight upload, AppIcon, and iPhone/iPad orientation metadata.

## Phase 3D acceptance tests

All four tests must pass on a real iPhone using the real Logto Email OTP flow.

### TEST 1 — first private save

Signed out → create Draft → Save → login required → Logto Email OTP → callback to app → consume `PendingSave` once → record exists exactly once.

### TEST 2 — logout and same-account relogin

Logout → private record hidden → login to same account → same issuer + `sub` → previous record visible again → no duplicate record.

### TEST 3 — session restore

Force quit → relaunch → restore session → same canonical identity → previous private record remains available.

### TEST 4 — cancelled authentication

Signed out → Draft → Save → login flow → cancel authentication → no persistence → Draft remains → a later unrelated login must not consume the cancelled `PendingSave`.

Record final status as `IDENTITY_3D_REAL_DEVICE_PASSED` only after all four pass. If an external issue blocks any test, record `IDENTITY_3D_BLOCKED` and name the specific blocker.

## Frozen identity and data ownership rules

- Fireseed User ID is the canonical app identity; external ownership scope is `(issuer, sub)`.
- Email is an attribute, never `ownerID`.
- Logout clears the session and hides private records while signed out; it does not delete local private records.
- Signed-out users may browse public and other non-private UI, but private records stay hidden.
- A `PendingSave` is consumed exactly once. Cancelling login invalidates its pending continuation.
- Identity, Backup, Sync, and Share are separate. Phase 3D adds no cloud sync or backup behavior.

## STAGING TestFlight identity configuration

- STAGING workflow support commit: `81ef749e054c7b5c23383d474240bcc1d821c54f` — `Support staging identity TestFlight builds`.
- `workflow_dispatch` inputs: `identity_environment`, `identity_endpoint`, and `identity_client_id`.
- A STAGING archive injects `FIRESEED_IDENTITY_ENVIRONMENT`, `FIRESEED_IDENTITY_ENDPOINT`, `FIRESEED_IDENTITY_ISSUER`, and `FIRESEED_IDENTITY_CLIENT_ID`.
- Production Identity defaults remain empty. Never hard-code a staging tunnel in project files.
- Callback URI: `com.fireseed.aiquicknote://oauth/callback`.
- Post-logout URI: `com.fireseed.aiquicknote://oauth/signed-out`.
- Phase 3D temporary tunnel (confirmed 2026-10-03): `https://python-stewart-horizon-produces.trycloudflare.com`. Cloudflare quick tunnels are temporary; verify that it is still active before dispatching a build.
- Native/Public Logto client ID: `woebxmgo960m5l0nl12ae`.
- Do not create or inject a client secret for a Native/Public app.
- Next planned TestFlight: Marketing version `0.1`, Build `6`, Identity environment `STAGING`.

## Current machine and repository state

- Development machine: Windows with NVIDIA RTX 5070 Ti; it has no macOS/Xcode and cannot create a native iOS archive locally.
- iOS archives continue to use the GitHub macOS runner. Keep GitHub Actions as CI and remote fallback after iOS development moves to the M5 Ultra Mac.
- At audit start, local `main` matched `origin/main` at `3147bfd0b125e79298f2533e00a684868c930170`. Audit fixes were pushed in scoped commits; use the audit report for tested implementation and CI evidence, and fetch before continuing on another machine.
- Preserve these untracked files; do not delete or commit them unless explicitly requested: `pelican-bicycle.svg`, `新建 Text Document.txt`.

## Next step and scope boundary

The only next workstream is to generate and install TestFlight Build 6 with Identity environment `STAGING`, then perform the four Phase 3D real-iPhone tests above. Do not return to Phase 3C or start new features, Sync, Backup, UI redesign, or Parser work.

Related detail: [Identity development spec](docs/fireseed-identity-v1-development-spec.md), [Phase 3C implementation record](docs/fireseed-identity-phase-3c.md), and [TestFlight release rules](docs/testflight-release.md).
