# Fireseed Identity V1 — Phase 3C Provider Integration

Phase 3C adds a real Logto provider behind the Phase 3B `IdentityProvider` boundary. The app target pins Logto Swift SDK `2.0.0-beta.1`; only `LogtoIdentityProvider` imports its SDK types. The default app provider is Logto in Debug and Release. UI fixtures and tests explicitly inject the existing mock; a missing/invalid Logto configuration never selects a mock identity.

## Configuration and local Logto setup

The generated app Info.plist reads `FIRESEED_IDENTITY_ENVIRONMENT`, `FIRESEED_IDENTITY_ISSUER`, `FIRESEED_IDENTITY_ENDPOINT`, `FIRESEED_IDENTITY_CLIENT_ID`, `FIRESEED_IDENTITY_REDIRECT_URI`, and `FIRESEED_IDENTITY_POST_LOGOUT_REDIRECT_URI` from the app target's build configuration.

- Debug defaults to `LOCAL`, the verified loopback issuer `http://127.0.0.1:3301/oidc`, and the local Logto endpoint `http://127.0.0.1:3301`. Its client ID is intentionally blank until a Native/Public application is created/configured in the local Admin Console.
- Release defaults to `PRODUCTION` with no issuer, endpoint, or client ID. No staging or production endpoint/client credential is invented or committed. `STAGING` and `PRODUCTION` accept HTTPS issuer/endpoint values through their respective build configuration; `LOCAL` accepts HTTP only for loopback hosts.
- In the local Logto Admin Console, configure a Native application with Authorization Code + PKCE, redirect URI `com.fireseed.aiquicknote://oauth/callback`, and post-logout redirect URI `com.fireseed.aiquicknote://oauth/signed-out`. Put only its public client ID in the local Debug build setting `FIRESEED_IDENTITY_CLIENT_ID`; do not configure a client secret.
- Logto Swift SDK v2 uses `ASWebAuthenticationSession` to receive its callback. The OS matches the auth callback to the initiating session; the app does not add a competing `onOpenURL` handler. Do not add the callback URI to other applications.

The local Logto server remains loopback-only. Its endpoint cannot be reached from a separate Mac CI runner or a physical iPhone via that loopback address; no network exposure, ATS exception, or local OTP test is part of this code change. A separate private HTTPS device transport/configuration decision remains necessary for real-device validation.

## Session and ownership

The SDK performs OIDC discovery, Authorization Code + PKCE, ID-token signature/issuer/audience/time validation, and stores ID/refresh tokens in Keychain. On restore, the provider refreshes through the SDK, obtains UserInfo over the authenticated session, and accepts only a nonempty `sub` from the configured issuer. Sign-in uses validated ID-token claims. Email is included only when `email_verified` is true; email is never used as an owner key. Authentication errors are reduced to safe app-level messages; codes, callback URLs, and token material are not logged. The SDK is currently a v2 prerelease, pinned to its published `2.0.0-beta.1` release.

`Record.ownerID` remains the OIDC `sub`; a nullable `ownerIssuer` scopes Core reads, writes, same-record updates, and restore. Old mock/local rows without an issuer are retained but are not silently adopted by a real issuer. Backup schema v3 adds only `ownerIssuer` beside the existing owner ID. Schema v2 remains readable for issuer-less/mock identities; a v2 backup cannot restore into a real issuer-scoped account, and a v3 backup from another issuer is rejected before writes. No authentication token, profile token, or credential enters the backup manifest.

First-save `PendingSave` handling is unchanged. Cancellation/failure does not persist the pending record; logout hides records without deleting/reassigning them or affecting system reminders, and does not initiate backup/upload/sharing.

## Validation boundary

Automated checks cover issuer+subject ownership and backup rejection, configuration selection/validation, subject mapping, verified-email handling, and Apple web-auth cancellation mapping. Native compilation and XCTest/UI suites are delegated to the repository's macOS iOS CI. The loopback Logto app/client provisioning and real Email OTP from a Simulator/iPhone are not claimed by this phase; verify them separately after entering the local public client ID and arranging an explicitly approved device-reachable endpoint.
