# Fireseed Identity V1 — AIQuickNote Integration Audit and Phase 3B Result

**Scope:** Phase 3A was a read-only audit. Phase 3B implements only the app-facing local identity semantics and owner safety needed before a real provider. No Logto SDK, real auth, identity infrastructure/configuration, or app data was changed.

## Phase 3A baseline findings (before this implementation)

## 1. Current implementation map

| Flow | Current code and observed behavior |
|---|---|
| Launch/session | `AIQuickNoteApp` creates `AppModel`; production init creates `IdentitySession`, `FileRecordStore(Application Support/records.json)`, then `QuickNoteCore` and reloads records synchronously. `IdentitySession` restores a JSON `IdentityUser` from `UserDefaults` key `identity.currentUser`; there is no async session restoration or resolving state. |
| User/auth | `IdentityUser` and `AuthProvider` are in `ios/QuickNoteCore/Core.swift`. App `LoginView` presents local test account choices and calls `MockAuthProvider`; no Logto/OIDC SDK or real authentication callback is in the app target. The mock provider returns fixed provider/account test identities. |
| Legacy session | If `identity.currentUser` cannot be decoded, `IdentitySession` reads `confirmedUserID`, substitutes the fixed mock “Test User 1” identity, records the old string as `legacyOwnerID`, and persists the substitute. `AppModel.init` then rewrites records with that old owner ID to the substitute ID using best-effort `try?`. This is an automatic ownership reassignment. |
| First save | `ReviewView.save` calls `AppModel.saveOrRequestIdentity`. `QuickNoteCore.save` rejects absent identity with `CoreError.identityRequired`; the app stores one `pendingSave` and completion closure in memory and presents `LoginView`. A successful mock sign-in persists the user, reloads, clears the pending record before saving it, saves through the same Core method, and calls the completion. |
| Draft/cancel | The review screen keeps the editable draft in SwiftUI state. Dismissing the login sheet does not persist it, so it remains visible while that screen stays alive. However, the separate `AppModel.pendingSave` and completion are not cleared on login-sheet cancel; a later unrelated sign-in can consume that stale save. A process termination loses this in-memory pending operation; no pre-auth draft persistence exists. |
| Record ownership | `Record.ownerID` is a required persisted `String` (default empty only for new in-memory drafts/fixtures). `QuickNoteCore.save` requires a confirmed ID and overwrites the incoming owner with it. Upsert matches both record UUID and current owner, so another owner's same-UUID record is not overwritten; it can result in an additional record under the current owner. |
| Read/search/detail | `QuickNoteCore.records` returns no records without identity and otherwise filters the single JSON store by exact `ownerID`. `QuickNoteCore.search(_:)` searches those filtered records. App search calls the static search function with `model.records`, which is populated through that owner-filtered method. Module lists and detail sheets are opened from `model.records`; there is no independent detail-by-ID route or owner check in `DetailSheet`. Static `QuickNoteCore.search(_:in:)` trusts its caller-provided array and is not itself an ownership boundary. |
| Reminders | The record stores reminder flags/state and an EventKit item identifier. After save, `ReminderService` creates a device/system reminder with record content and due date; no Fireseed owner metadata or owner partition is written to EventKit. Sign-out does not delete the EventKit item. Record reads remain owner-filtered, but the mirrored reminder is outside that filter and can remain visible in the system Reminders app. |
| Export/backup | Export and backup receive `model.records` (already filtered) and the current mock user. `records.json` in the archive includes each `ownerID`; `users.json` includes `IdentityUser` metadata. No password or OAuth token is in this app format. `ExportManifest.schemaVersion` is `1`; backup reuses the same archive/manifest schema. |
| Restore | Import validates the archive and asks to replace the current user's records. `BackupService.validateAndRead` validates shape/counts but not ownership. `replaceCurrentOwnerRecords` removes the active owner's records, then overwrites **every imported record's** owner ID with the active owner. It ignores the decoded `users` array at the call site. Thus a backup from another user (or one containing multiple owners) can be claimed by whoever is signed in at restore time. With no signed-in user, restore throws identity-required rather than invoking the first-save login flow. |
| Sign-out/switch | `AccountView` invokes `AppModel.signOut`, which clears both UserDefaults identity keys and the in-memory pending operation, then reloads. `QuickNoteCore.records` returns `[]`; the physical JSON records are not deleted or rewritten. Signing into a different mock account filters to that account. Signing back into the original fixed mock ID makes its records visible again. |
| Delete/reset | No app-level record delete, local-data reset, or account-delete flow was found. The implemented account action is mock sign-out. OS-level app deletion/data removal is outside the app code and the installed device's actual files cannot be inspected in this audit. No claim is made about external EventKit data deletion. |

Relevant files: `ios/AIQuickNote/AIQuickNoteApp.swift`, `ios/QuickNoteCore/Core.swift`, `ios/QuickNoteCoreTests/CoreTests.swift`, `ios/AIQuickNoteUITests/NavigationRegressionTests.swift`, `ios/AIQuickNote.xcodeproj/project.pbxproj`, `ios/Package.swift`, and `infra/identity/docker-compose.yml`.

## 2. Identity and owner semantics / legacy classification

- Current production app identities are **authenticated mock identities**, not real users: fixed IDs and mock provider subjects from `MockAuthProvider`, persisted in `UserDefaults`. Provider/account slots can represent multiple users; IDs are deterministic, not generated per install.
- `QuickNoteCore` also currently declares a generic `IdentityProvider` enum, `AuthProvider` protocol, and `MockAuthProvider`. Despite the protocol name, this is not a Fireseed/OIDC provider boundary; it is the test login implementation and should not be confused with the new IdentityKit contract.
- A prior session value under `confirmedUserID` is classified in code as a **legacy generated/local owner string** and automatically mapped to the fixed mock Apple test account on initialization. The mapping is not evidence that a future Fireseed account owns those records.
- Debug UI tests use a **test/demo owner** (`ui-test-owner`) and `MemoryRecordStore`; this is not the production store. Core tests also use fixture owners such as `owner` and `user-1`.
- `Record`'s empty default owner is used for new drafts and fixtures; `QuickNoteCore.save` will not persist a draft without confirmed identity. No anonymous owner identity is created by the normal save path, so an `anonymous owner` category is not evidenced by current code.
- Production records live together in one `records.json`; no per-user file/database or per-install owner generator exists. Owner visibility is a string equality filter. Records survive app sign-out physically; the current account cannot see them while signed out, and another mock ID cannot see them through app record/search paths.
- The app's `UserDefaults` stores mock profile fields (including mock email/provider subject), not a credential/session token. A future real provider must not keep OIDC tokens in `Record` or reuse this mock profile persistence as secure token storage.
- There is no evidence in source of actual installed-device record contents or all historical versions. The only legacy categories this audit can establish are those above; it cannot assert which category/count exists on the user's phone.

## 3. Risks found

1. **Unsafe automatic legacy reassignment:** legacy owner IDs are silently rewritten to a synthetic mock user; this cannot be carried forward as a Fireseed account mapping.
2. **Cross-account backup claim:** restore discards incoming ownership and labels all incoming rows with the current user. A foreign backup becomes visible to the restoring user. Current archive schema does not identify a Fireseed issuer/owner, so old and future Fireseed backups would not be distinguishable by identity.
3. **Stale pending save after cancel:** the view draft remains, but the app-level pending copy is still armed after the login sheet is dismissed. A later sign-in can save it without a fresh save action. It is not durable across process death.
4. **EventKit is device/system scoped:** app owner filtering cannot hide or revoke a reminder already written to the user's system Reminders store. Sign-out does not remove reminders.
5. **Restore is not unified with first-save auth:** an unsigned restore fails with an error instead of preserving the selected restore operation and requesting sign-in.
6. **Async identity bootstrap is absent:** synchronous mock restoration currently allows immediate record loading. Replacing it with network-backed restoration without a resolving gate risks showing stale/empty/transient state or loading data before identity is established.
7. **Ownership domain is not issuer-qualified in records:** the product baseline defines `sub` as owner within the configured Fireseed issuer. A single local dataset must not silently switch between local/staging/production issuers; equal subject strings from different issuers are not the same identity.

## 4. Legacy migration policy (initial audit recommendation)

This is a pre-public-release alpha and the found production auth is synthetic. Do not build a general account-linking/migration framework and do not silently adopt mock/legacy records by email, display name, or matching subject text.

**Recommended internal-test cutover:** keep the old `records.json` untouched until the user has a chance to export it; for the Phase 3B identity-enabled test build, use an explicit one-time “start with a clean identity-owned store” cutover after the operator has exported any wanted test data. If retention is required, stop and make a deliberate one-time local adoption/import choice with a validated backup and explicit confirmation; never infer that a Fireseed `sub` maps to a mock identity. Do not rewrite arbitrary owner IDs in place.

| Case | Required behavior |
|---|---|
| 1. Fresh install, no records | Start signed out; browsing remains available. First successful save writes the Fireseed `sub` as `ownerID`. |
| 2. One legacy owner | No automatic adoption. For this unreleased alpha, prefer operator-export + clean cutover. If retention is chosen, require explicit, one-time local adoption after sign-in; preserve a recoverable pre-migration export and record the decision. Email equality alone is not proof. |
| 3. Multiple legacy owners | Never mass-reassign. Preserve each owner namespace in an export/quarantine or require an explicit per-owner disposition; do not show records to a newly signed-in Fireseed user by default. |
| 4. Legacy backup | Current v1 archive has no reliable identity issuer/owner marker. Treat it as legacy/unverified; do not auto-restore into an authenticated account. Require explicit import/adoption decision or leave unchanged. |
| 5. User A signs out, B signs in | Keep A's stored rows and `ownerID`; B's `records()`/search/details show only B's `sub`. No delete/relabel. EventKit reminders remain a separate system-level behavior. |
| 6. A signs back in | If the same configured issuer returns the same `sub`, A's rows are visible again. |
| 7. Auth canceled during first save | Do not persist. Keep the draft in its current review UI; clear the armed continuation so a future unrelated login cannot save it. A later explicit Save may start a new auth attempt. |

No account deletion policy is implemented. Account deletion is out of Phase 3B; local record deletion/reset needs an explicit user-facing product policy and must not be conflated with Logto sign-out or account deletion.

### Phase 3B cutover decision (final)

Use a clean identity-owned store for this unreleased internal test build. Existing legacy rows and legacy session keys remain untouched on disk but are ignored by the new identity path; they are never mapped to either deterministic mock user. There is no automatic migration or runtime deletion. Before reinstall/reset during development, export any wanted legacy data through the old build; an OS-level app-data removal is an explicit manual developer action and is not performed by the app. System Reminders remain device-level and may remain after sign-out.

## 5. Minimum Phase 3B design (implemented locally)

### IdentityKit / boundaries

Keep the existing `Record.ownerID: String` and `IdentityGate.confirmedUserID` seam. Phase 3B supplies deterministic local mock IDs only; a future provider may supply the authenticated OIDC `sub` from the single configured Fireseed issuer. Email, Apple subject, Google subject, username, and display name are attributes/authentication methods, never owner IDs. Keep provider SDK types and tokens inside an app-facing identity adapter; Core receives only the stable string and must not import Logto.

The small public surface should be limited to:

```text
IdentityState = resolving | signedOut | signedIn(FireseedUser)
FireseedUser = stableUserID(sub), optional email, optional displayName
restoreSession() / signIn() / signOut()
```

Implemented in `ios/AIQuickNote/FireseedIdentityKit.swift`; launch starts resolving, ignores previous identity keys, then loads only the restored mock user's rows. Two deterministic internal-test users are selected through the existing debug launch argument. No real credentials or provider tokens are stored. Cancel/failure disarms the one-shot pending-save continuation while the editable ReviewView draft stays on screen; repeated sign-in cannot claim that old save. Successful sign-in consumes the pending operation before its sole Core write. User switching filters module/search data by `ownerID`; stale detail sheets close when their record is no longer visible. Sign-out clears in-memory visibility before provider cleanup and never deletes records or system reminders.

Avoid building profile/linking/account-management UI. Store real provider session material only through the chosen SDK's supported secure session storage. No secrets belong in the public iOS client configuration.

### First save

```text
editable Draft → explicit Save
  signedIn(user) → Core.save(draft with ownerID supplied by Core = user.sub)
  signedOut → keep Draft only in current view memory → begin one sign-in operation
    success → consume that exact pending operation once → Core.save → return to caller
    cancel/failure → no Core write; leave the view's Draft editable; disarm pending continuation
```

Keep the single persistence path in `AppModel`/Core; do not add a second auth-specific record writer. Bind pending save to one operation identifier and make completion single-consumption on the main actor (or equivalent serialization). A second save while auth is pending must not replace or duplicate the first silently. Restore/import is also a persistent write: require a confirmed identity and apply the same ownership validation, but do not auto-import or auto-upload.

### Session restore and user switching

At launch begin in a resolving/bootstrap state with private `model.records` empty. Call `restoreSession`; only after a valid provider session yields a `sub` set Core identity and load records. If absent/invalid, transition to signed out and leave disk untouched. Keep public browsing available during restore; do not query/display private rows under the previous in-memory user's identity. Avoid presenting the login UI merely because the app launches.

On sign-out, immediately stop exposing the current user's in-memory records and set signed out, then complete provider sign-out/session cleanup. Do not delete, upload, or rewrite rows. On another sign-in, reload using only that user's `sub`; returning to the same issuer+subject restores that user's view.

### Backup/restore

Phase 3B restore must not repeat `replaceCurrentOwnerRecords`' unconditional reassignment. The local test backup format is v2 with a stable mock `ownerID` marker; restore requires an exact owner match, validates all rows and rejects archives with `users.json`, and preserves (does not rewrite) `ownerID`. Mismatches are rejected before replacing any rows. Archives without the marker (including v1 exports/backups) are rejected as legacy; no adoption flow is included. Backup and export/sharing remain independent from sign-in: login never initiates either. A future real-provider migration must qualify the marker by issuer as well as `sub`; that is Phase 3C, not implemented here.

### Environment and local device networking

- Current Compose binds Logto ports to `127.0.0.1`; Compose defaults are 3001/3002, while the tracked local README records this machine's ignored host port override as 3301/3302. Mailpit is also loopback-bound. No app endpoint/client configuration exists yet.
- A Simulator can use loopback only when Logto is reachable on the same Mac host as that Simulator. The current Windows-hosted loopback is not reachable as `127.0.0.1` from a different Mac/CI host. A physical iPhone's `127.0.0.1` is the phone itself; the current Windows loopback binding cannot serve it.
- For a physical-device development test, use a private LAN-only HTTPS reverse proxy / stable development hostname to the local Logto service, configure Logto's public endpoint/issuer and OIDC discovery to that exact externally reachable HTTPS origin, register the exact native redirect and post-logout redirect, and allow only the private network/device through Windows Firewall. Keep PostgreSQL and Mailpit private and unpublished. Verify discovery `issuer`, authorization/token endpoints, callback and logout round-trip all use the same authority; changing only the iOS URL is insufficient.
- Prefer a development TLS certificate trusted by the test phone. Keep production ATS protections enabled; no global arbitrary-load exception, no production HTTP endpoint, and no router/public port-forwarding. If a narrowly-scoped local-development exception is ultimately required, isolate it to Debug configuration and the exact local host, document why, and remove/verify it absent from Release. Apple documents ATS requirements and local-network-specific behavior in [Preventing Insecure Network Connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections) and [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).
- Debug may use the local Fireseed issuer/client; staging/release need distinct issuer/client configuration. No production issuer currently exists. The current local test subject and email are test data and must not be hard-coded.

### Logging/privacy

Log only sanitized operation/state transition, success/failure category, and an opaque correlation ID. Never log OTPs, credentials, authorization codes, PKCE verifier/challenge, access/refresh/ID tokens, or full email. Do not emit raw `sub` in ordinary analytics; if correlation is unavoidable use a short-lived keyed hash and keep it out of export/share paths.

## 6. Phase 3C boundary (not started)

The following are explicitly deferred to Phase 3C. No SDK/package dependency, native redirect, production/local endpoint setting, real OIDC transaction, or token storage is part of this change:

1. `ios/AIQuickNote/AIQuickNoteApp.swift` — replace mock provider callbacks with a selected real-provider adapter while retaining safe first-save continuation.
2. New `ios/FireseedIdentityKit/Package.swift` — small package boundary and pinned Logto Swift SDK dependency.
3. New `ios/FireseedIdentityKit/Sources/FireseedIdentityKit/IdentityKit.swift` — `FireseedUser`, `IdentityState`, and minimal provider contract.
4. New `ios/FireseedIdentityKit/Sources/FireseedIdentityKit/LogtoIdentityProvider.swift` — SDK/OIDC adapter only; no Core model changes.
5. `ios/AIQuickNote.xcodeproj/project.pbxproj` — link the local IdentityKit package and register the exact native callback URL/configuration. Keep local endpoints in Debug-only configuration; no public client secret.
6. `ios/QuickNoteCore/Core.swift` — only if needed, extend backup ownership marker from local mock `ownerID` to issuer+sub. Keep `Record.ownerID` a string; do not add SDK types or token fields.
7. `ios/QuickNoteCoreTests/CoreTests.swift` — owner isolation and backup-mismatch/no-write regression tests.
8. `ios/AIQuickNoteUITests/NavigationRegressionTests.swift` — first-save, cancel, pending operation, session bootstrap, logout and account-switch UI regression coverage.
9. Provider-independent tests for real adapter state/cancel/error handling; no real credentials in tests.

Do not touch parser, speech, search semantics, reminders implementation, UI skin/layout, database schema, cloud sync, or production environment endpoints in this integration pass. `Record` already has a string owner field and Core already gates saves and filters reads, so a broader Core redesign is not required.

## 7. Phase 3B regression coverage and validation

Existing parser/search/save/export tests remain unchanged apart from ownership-related cases. This pass adds Core owner-isolation and backup mismatch/no-write tests plus app-target tests for resolving/signed-out restore, same-owner return, and data retention on sign-out. Add or extend tests to cover:

1. Fresh install starts resolving then signed out; browsing does not prompt.
2. First explicit save opens local test sign-in, and writes only after successful authentication.
3. Pending operation is one-shot and tied to its request ID.
4. Cancel/failure leaves the visible ReviewView draft and clears its pending continuation.
5. Repeated save taps during one auth transaction cannot replace or duplicate the pending operation.
6. Sign-out leaves persisted records/reminders untouched but clears visible records; the same user sees their own rows again after reauthentication.
7. User B cannot see A's list/search/result/detail; switching back restores A's view.
8. Session restore happens before private records load; absent/invalid session stays signed out without deleting rows.
9. Reminder linking occurs after owner-authenticated local save; reminder entries remain system/device-level on sign-out.
10. Owner-marked v2 backup round-trips; foreign, mixed-owner, `users.json`, and legacy/unmarked archives are rejected before writes.
11. Existing Core parser/search/save/export and UI navigation suites remain green.
12. Real Email OTP on Simulator/iPhone is deliberately not part of this mock-only Phase 3B validation; it belongs in Phase 3C after endpoint/transport choices.

Validation performed on this Windows host: targeted source-reference checks and `git diff --check`. `swift` and `xcodebuild` are unavailable, so Core tests, app unit tests, Simulator build, UI tests, and runtime checks are pending macOS CI. No Docker/Logto infrastructure was restarted or changed.

## 8. Explicit non-goals and decisions before implementation

**Non-goals:** Logto SDK/real OIDC (Phase 3C); Apple/Google configuration; account linking/profile/avatar; passkeys/MFA/organizations/RBAC; cloud sync or automatic upload; app account deletion; parser/search/reminder feature work; UI redesign; broad Core/persistence refactor.

**Human/product decisions:**

1. Legacy-data policy for Phase 3B is clean identity-owned cutover: retain old records/keys on disk and ignore them; no automatic migration or runtime deletion. A developer may manually export first and remove app data during local development.
2. Choose the allowed physical-iPhone development transport (private LAN HTTPS proxy + trusted dev certificate is recommended) and stable local hostname/issuer. This is an environment/operator choice; do not expose Compose ports publicly.
3. Legacy/unmarked archives are rejected; no import-as-new-data/adoption UI is included.
4. Confirm that system Reminders are intentionally device-level and may remain after Fireseed sign-out. If not acceptable, define an explicit reminder cleanup/visibility policy separately; do not silently delete them during identity changes.

## 9. Validation and audit limits

- Repository baseline was `e12dea0d8f11caab34760f0075129d412c55b189`; worktree was clean before the audit document was added.
- The supplied Phase 2 result is accepted as the local Identity infrastructure baseline; this audit did not repeat Docker/Logto tests or read credentials, OTPs, app-installed device data, or the ignored local `.env`.
- This Windows environment exposes Python but not `swift` or `xcodebuild`; native Swift Core tests, Simulator build, and Xcode UI tests cannot run here. Phase 3B must obtain native macOS CI evidence before claiming those checks.
- Phase 3B has static source/project checks only; this does not establish Swift compilation, app/runtime, or physical-device behavior.
