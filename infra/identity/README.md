# Fireseed Identity — LOCAL

Disposable local Logto OSS and PostgreSQL only. No app integration, provider delivery, staging, or production configuration is included. The compose file follows Logto's official v1.43.0 image/seed pattern, with loopback-only ports and a persistent named PostgreSQL volume.

## Prerequisites

- Docker Desktop with Docker Compose v2 and its Linux container engine running.
- PowerShell 7 recommended.
- Logto's self-hosting guide recommends 2 vCPU, 8 GiB RAM, and 256 GiB disk; smaller machines may run slowly or fail.

## First start

```powershell
Copy-Item infra/identity/.env.example infra/identity/.env
```

Set `POSTGRES_PASSWORD` in `infra/identity/.env` to a private random value of at least 32 characters using only letters, digits, `_`, or `-`. The constraint keeps the password safe inside the PostgreSQL URL without encoding. `.env` is ignored by Git. Do not put real credentials in `.env.example`.

```powershell
./infra/identity/scripts/identity.ps1 start
```

The first startup downloads the pinned images and seeds the dedicated database through Logto's bundled CLI. Open the Admin Console at the configured local endpoint and create the local operator on the welcome screen. The core endpoint hosts OIDC discovery at `/oidc/.well-known/openid-configuration`.

The Compose seed uses Logto's `--dapc` option to avoid an outbound Have I Been Pwned dependency for the initial local Admin Console account. This affects the admin tenant only; it does not configure or enable app end-user password login.

The local Compose stack includes Mailpit as a development-only SMTP sink. Its UI is loopback-bound at `http://127.0.0.1:18025`; Logto reaches its SMTP service at `mailpit:1025` inside Compose. Configure the official SMTP connector with no credentials for that isolated network. Mailpit captures messages rather than delivering them externally; Logto still generates and verifies real OTPs. Do not use this setup for production.

The Phase 2 local test uses email verification code only, with password sign-in disabled, automatic email/phone account linking disabled, and no Apple/Google connectors. The Admin Console operator is infrastructure administration, not a Fireseed end-user account. The Native/Public client uses Authorization Code + PKCE and loopback callback URIs for the local smoke harness.

To run the interactive OIDC test, ensure Logto and Mailpit are running, then execute `node tests/identity/oidc-pkce-smoke.mjs`. Open the printed authorization URL in a browser, complete the real email verification code from Mailpit, and wait for the local callback. The harness checks state, nonce, issuer, audience, expiry, and ES384 signature against the local JWKS, then prints only the non-secret `sub`; it never prints tokens or verification codes. Use the same flow after explicitly logging out to verify the same subject is returned. Repeat after restarting Logto/PostgreSQL to verify identity persistence. This remains a development-only flow and must not be connected to production email.

## Commands

```powershell
./infra/identity/scripts/identity.ps1 start
./infra/identity/scripts/identity.ps1 stop
./infra/identity/scripts/identity.ps1 status
./infra/identity/scripts/identity.ps1 logs
./infra/identity/scripts/identity.ps1 health
./infra/identity/scripts/identity.ps1 smoke
./infra/identity/scripts/identity.ps1 reset
```

`stop` retains identity data. `smoke` checks Postgres/Logto/Admin/OIDC, writes a temporary marker to the LOCAL identity database, restarts Postgres and Logto, verifies the marker survived, then removes it. `reset` requires typing `RESET`, deletes the Compose project's LOCAL named PostgreSQL volume, and starts a fresh database. It permanently deletes local test identities in that volume.

## Verified Windows runtime (2026-09-25)

- Docker Desktop 4.92.0, Linux engine 29.8.0, Compose v5.5.1; WSL 2.7.14 with Ubuntu running as WSL 2.
- Logto OSS 1.43.0 completed seed/migrations and passed its health check; PostgreSQL image `postgres:17-alpine` ran PostgreSQL 17.11 and stayed healthy.
- Windows reserves host TCP ports 3001/3002. This machine's ignored `.env` uses loopback ports 3301/3302 instead; PostgreSQL has no host port mapping. Other hosts can keep the documented 3001/3002 defaults.
- Verified `start`, `health`, `smoke`, ordinary `stop`/`start` persistence, and `reset`. The smoke marker survived PostgreSQL/Logto restarts and was removed. Stop/start retained the named volume and all 79 application tables. Reset replaced that local volume and returned both services to healthy running state.
- Runtime fixes: the health check accepts the Admin Console's expected 302 redirect; the PowerShell Compose wrapper forwards native flags; local endpoint parsing reads the correct regex capture; and the temporary smoke table enables RLS so Logto can restart safely.
- Phase 2 preparation: `identity.ps1 health` now reads the endpoint value from its single regex capture and accepts the Admin Console's 302 without PowerShell's redirect-handling failure. The local-only Mailpit v1.27.4 service starts with host ports 11025 (SMTP) and 18025 (UI); Windows reserves 1025 on this machine.
- The local Admin Console operator was created by the user after Phase 1. Phase 2 created one local test user through real Email OTP registration and verified fresh Email OTP sign-in both before and after a PostgreSQL/Logto restart; no AIQuickNote data is present.
- The first image pull coincided with a full Windows system drive and Docker reported read-only/content I/O errors. After freeing space and re-pulling the same pinned Logto image, its Node runtime (v22.23.2) and the service started normally.

## Providers and current limits

The local SMTP connector targets Mailpit without credentials; its required `auth` object is configured as `{"type":"login"}` and SMTP operation logging is disabled. The local Native/Public client is configured for Authorization Code + PKCE. Email verification code is enabled for sign-up and sign-in, and password sign-in remains disabled. Apple and Google remain unconfigured. The real Email OTP registration, a fresh signed-out OTP re-login, and a fresh OTP re-login after PostgreSQL/Logto restart all completed through PKCE and returned the same local subject `gty8xvsquh6d` (non-secret OIDC `sub`). The existing `identity.ps1 smoke` and post-restart health checks also passed. **Phase 2 result: `IDENTITY_EMAIL_LOOP_READY` (local development only).** Do not expose production sign-up until duplicate-email social-registration behavior is checked against the pinned Logto version.

## Version and upgrade

- Logto OSS: `svhd/logto:1.43.0`.
- PostgreSQL: `postgres:17-alpine` (major pinned to match Logto's v1.43.0 upstream Compose example).
- The Logto tag is an explicit patch version. PostgreSQL's official major tag receives patch updates. Before shared use, capture immutable platform-specific digests.
- Before upgrading, back up the LOCAL named volume, rehearse with a separate restored volume, and run the target version's official `logto db alteration deploy` command before starting the new server. Roll back the database backup together with the old image if schema changes are incompatible.

For this single local instance, official connectors ship with the pinned Logto image. Logto's shared connector-folder mount and `connector add --official` setup are documented for deployments that run multiple instances or explicitly install connectors; add that volume/init step if this local setup grows to that shape.

The pinned versions were checked against the [official v1.43.0 Compose file](https://github.com/logto-io/logto/blob/v1.43.0/docker-compose.yml), [Logto OSS upgrade guide](https://docs.logto.io/logto-oss/upgrading-oss-version), and [database alteration CLI guide](https://docs.logto.io/logto-oss/using-cli/database-alteration).

Detailed product/trust decisions are in [`docs/fireseed-identity-v1-development-spec.md`](../../docs/fireseed-identity-v1-development-spec.md); logging and changes are governed by [`docs/fireseed-identity-logging-change-protocol.md`](../../docs/fireseed-identity-logging-change-protocol.md).
