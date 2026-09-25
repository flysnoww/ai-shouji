# Fireseed Identity V1 Development Spec

Status: Phase 2 in progress; local identity infrastructure and test mail sink only. No end-user authentication loop is verified yet.
Baseline: `34c85b4c0e8150e25ff0f77d07ceed103a35dd8a` (AIQuickNote V1 UI regression candidate).
Last upstream review: 2026-09-23.

## Goals

- Define a reusable Fireseed identity boundary for future apps.
- Run an isolated, disposable Logto OSS + PostgreSQL environment on a developer machine.
- Keep this work independent of AIQuickNote domain behavior and its data store.
- Keep identity, backup, sync, sharing, and domain data separate.

## Non-goals

No production authentication integration, cloud deployment, staging environment, app record migration, backup/sync changes, custom auth server, phone/SMS auth, password sign-in, organizations, RBAC, or app-specific authorization.

## Frozen principles

- A Fireseed user is stable; authentication methods are replaceable credentials.
- Identity establishes ownership only. It does not imply backup, upload, sync, or sharing.
- Domain applications may depend on IdentityKit. Identity services never depend on domain services.
- Anonymous browsing remains allowed. Any future persistent private save must pass a confirmed-identity gate.
- Logout clears the identity session only; it never deletes or reassigns local app records.
- Account deletion and app-data deletion are separate, explicit user decisions.

## Local architecture

```text
future app -> Fireseed IdentityKit -> IdentityProvider contract -> Logto Swift SDK v2
                                                        -> self-hosted Logto v1.43.0
                                                           -> dedicated PostgreSQL 17
```

Phase 1 runs only on the local Windows developer machine through Docker Compose. The official Logto OSS image is pinned to `svhd/logto:1.43.0`; PostgreSQL is pinned to major tag `postgres:17-alpine`, matching the upstream v1.43.0 demonstration Compose file. The database is isolated in a named Docker volume and is not AIQuickNote storage. The two local HTTP endpoints bind to loopback only. Logto's supported CLI seed command initializes the database. Built-in connectors/configuration live with the Logto image/database; no custom connector volume is needed in this phase.

The upstream OSS Compose file is explicitly demonstration-only; this repository adds a persistent named database volume, local-only port binding, required secret variables, health checks, and smoke commands. These settings are for local development, not production deployment.

## Canonical user ID

Use the OIDC `sub` issued by this self-hosted Logto tenant as the canonical Fireseed user ID. Logto documents its user `id` as a unique generated identifier; for one issuer, this is the subject identifier apps receive. Persist `sub` as the eventual owner ID, never an Apple subject, Google subject, email, username, or display name. Do not add a mapping database without a demonstrated need.

The subject is stable within this Logto identity authority, not a promise that independently seeded local, staging, and production tenants share IDs. Environments are separate identity namespaces. Moving an account to another issuer needs an explicit verified migration/linking process; do not silently rewrite local record owners. AIQuickNote's existing local mock owner IDs and record ownership remain untouched in this phase.

## V1 authentication methods

1. Email verification code / passwordless, through a configured Logto email connector.
2. Sign in with Apple, through a configured Logto social connector.
3. Google Sign-In, through a configured Logto social connector.

No end-user password authentication is enabled by the Fireseed V1 configuration. The Admin Console operator account is infrastructure administration, not an app authentication method. The local environment does not contain email delivery or Apple/Google credentials, so those flows are not claimed as configured or tested. Passkeys remain compatible but are not a V1 blocker.

## Linking and sensitive changes

- Automatic account linking by matching email/phone must remain disabled.
- Linking an additional provider through a signed-in account must require explicit user action, recent identity verification, and successful authentication of the new provider. The Account API social-linking flow exposes separate verification records for the current account and the new provider identity.
- Upstream documents that disabling automatic linking still shows a manual link-or-create choice during social sign-up when an email/phone matches. Its public docs do not establish that this initial-registration branch satisfies Fireseed's recent-verification requirement. Treat that branch as unresolved and do not approve production sign-in until it is verified against the pinned version and safely constrained. The later IdentityKit must use the authenticated Account API flow for linking.
- Sensitive identifier and social-link changes require Logto verification records. Never build a bypass around Logto's checks.
- Never remove the final usable authentication method. Logto documents a last-sign-in-method check for social unlinking; nevertheless, the IdentityKit must present/retain an alternative method and handle server rejection. Do not rely on unverified behavior for a custom unlink path.

## Minimal future IdentityKit contract

The Swift API is deferred until integration design. The Phase 2 app-facing semantics are intentionally small:

- `IdentityState`: `signedOut` or `signedIn(user)`
- `FireseedUser`: `stableUserID` (OIDC `sub`), optional `email`, optional `displayName`
- operations: `signIn()`, `signOut()`, `restoreSession()`

No Swift API or SDK is implemented in Phase 2. A later adapter keeps Logto SDK types and endpoints behind this small contract.

## Trust and data boundaries

The identity service may store canonical user ID, verified identifiers, name/avatar metadata, provider bindings, sessions/tokens, security/recovery data, lifecycle metadata, and minimal account-level preferences. It must not store QuickNote/Inventory/Health/language-learning records, attachments, private media, backup archives, synchronization payloads, or marketplace data. Avatar binary storage is not required.

PostgreSQL in this environment is only Logto identity infrastructure. Credentials are local `.env` values, excluded from Git. No production secrets or domains are allowed here.

## Logout and deletion

- Logout ends the client/Logto identity session as configured. Local app records remain available to their existing owner; logout never deletes or reassigns them.
- Deleting a Fireseed account requires a future explicit confirmation and recent verification. It must clearly explain consequences for sign-in and account metadata.
- Logto Account API covers end-user profile, identifiers, social identities, MFA, and sessions; account deletion is documented under Management API / a separately configured deletion flow, not a direct self-service Account API delete endpoint. A future IdentityKit deletion adapter therefore needs a narrowly scoped trusted server-side operation. This phase implements none of it.
- Local app-data deletion remains a separate explicit action governed by each app's retention/export rules.

## Environments

Only LOCAL is implemented. LOCAL, STAGING, and PRODUCTION must later have distinct issuer/endpoints, client credentials, database, secrets, and operational access. No environment shares a production database. Switching environments is configuration selection in the future app adapter; it is never an implicit migration of user IDs or app data.

## Logging and security

Follow `docs/fireseed-identity-logging-change-protocol.md`. Never log passwords, verification codes, access/refresh/ID tokens, OAuth codes, provider credentials, private keys, or complete authorization URLs. Keep the local admin endpoint loopback-bound. No Apple/Google/email provider secrets are checked in.

## Upgrade and migration

- Pin Logto `1.43.0`; pin PostgreSQL major 17. Image digest pinning is desirable for release reproducibility, but this development setup uses official explicit version tags and documents that tags can be republished. Before a shared or production deployment, capture and enforce platform-specific immutable digests.
- Before each Logto version change: export/backup the named local database volume, read the release notes, verify PostgreSQL compatibility, run the new image's supported `logto db alteration deploy` (or the release's documented equivalent) against a restorable copy, smoke test, and only then switch the local pin. Logto's documented upgrade path requires database alterations.
- A rollback may require restoring the pre-upgrade database snapshot; never assume a newer schema can be read by an older Logto binary.
- Canonical-ID migration between issuers requires a verified account mapping/re-authentication plan. No ownerID migration is included now.

## Verified upstream assumptions

- Current stable release at review: Logto OSS `v1.43.0`, published by the upstream Logto repository. Its official demo Compose uses `svhd/logto` and PostgreSQL 17. The demo is explicitly not for production.
- Logto OSS defaults to ports 3001 (core) and 3002 (Admin Console), and officially recommends CLI database seeding.
- Logto Swift SDK v2 is currently documented as `2.0.0`, using `ASWebAuthenticationSession`; no SDK is added in this phase.
- Logto's built-in email service is Cloud-only for OSS users; local development uses the official SMTP connector pointed at a loopback-only Mailpit sink. Mailpit captures, but does not externally deliver, Logto-generated verification emails.
- Local operator sign-in, SMTP connector, native app client, email-only sign-in settings, and end-user OTP flow are not yet verified in Phase 2.
- Account API sensitive operations use short-lived verification records. Social linking requires both recent verification of the current user and verification of the new social identity.
- Automatic email/phone matching can be disabled, but the manual first-registration linking branch needs a pinned-version security check as described above.
- Logto self-hosting documentation lists substantial recommended resources (2 vCPU, 8 GiB RAM, 256 GiB disk). A typical developer laptop may run below this recommendation; record actual resource behavior during the pending local runtime smoke check.

Primary references reviewed on 2026-09-23:

- [Logto OSS releases](https://github.com/logto-io/logto/releases)
- [Official v1.43.0 Docker Compose](https://github.com/logto-io/logto/blob/v1.43.0/docker-compose.yml)
- [Logto OSS getting started](https://docs.logto.io/logto-oss/get-started-with-oss)
- [Logto deployment and configuration](https://docs.logto.io/logto-oss/deployment-and-configuration)
- [Logto CLI and database alteration](https://docs.logto.io/logto-oss/using-cli)
- [Logto OSS upgrade guide](https://docs.logto.io/logto-oss/upgrading-oss-version)
- [Logto Swift SDK quick start](https://docs.logto.io/quick-starts/swift)
- [Logto social account linking](https://docs.logto.io/end-user-flows/sign-up-and-sign-in/social-sign-in)
- [Logto Account API](https://docs.logto.io/end-user-flows/account-settings/by-account-api)
- [Logto Account settings options and account deletion boundary](https://docs.logto.io/end-user-flows/account-settings)
- [Logto user data and ID](https://docs.logto.io/user-management/user-data)

## Open questions / blockers

1. Sign into the local Admin Console in the active Codex browser, then configure the Mailpit SMTP connector, native/public app client, exact redirects, and email-verification-code-only sign-in.
2. Complete signup, logout/re-login, and Logto/PostgreSQL restart tests; compare the same issuer-scoped `sub` each time.
3. Verify Logto `1.43.0` manual duplicate-email account-linking branch meets Fireseed's recent-verification constraint before enabling social sign-up for real users.
4. Verify final-method deletion behavior through end-user Account API for every enabled authentication method before shipping IdentityKit unlink controls.
5. Immutable image digests should be captured for each target OS/architecture before shared CI or non-local deployment.

## Scope freeze

No edits to AIQuickNote business logic, parser, speech, records, ownerID semantics, local persistence, search, reminders, backup, sharing, skins, or tests are made by this identity phase.
