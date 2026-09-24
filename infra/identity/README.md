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

The first startup downloads the pinned images and seeds the dedicated database through Logto's bundled CLI. Open `http://127.0.0.1:3002` and create the local Admin Console operator on the welcome screen. The core/OIDC endpoint is `http://127.0.0.1:3001`; its discovery document is `http://127.0.0.1:3001/oidc/.well-known/openid-configuration`.

The Compose seed uses Logto's `--dapc` option to avoid an outbound Have I Been Pwned dependency for the initial local Admin Console account. This affects the admin tenant only; it does not configure or enable app end-user password login.

No app client or end-user provider flow is configured by this local foundation. Before any future local app-auth test, verify the Logto Sign-in experience explicitly: use email verification code only, keep password sign-in disabled, disable automatic email/phone account linking, and leave Apple/Google connectors absent until their test credentials and linking controls are reviewed. Creating the Admin Console operator is not a Fireseed end-user account test.

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

## Providers and current limits

Email verification-code delivery requires an email connector and working mail service. Apple and Google require provider-side applications and credentials. None are supplied or tested here. The Sign-in experience must disable automatic account linking by email/phone. Logto still presents a manual link-or-create option in a duplicate-email social-registration flow; its public docs do not establish that this branch performs the required recent verification. Do not expose production sign-up until this is checked against the pinned Logto version. Future IdentityKit linking should use the signed-in Account API flow with fresh verification of both the existing account and the new provider identity.

## Version and upgrade

- Logto OSS: `svhd/logto:1.43.0`.
- PostgreSQL: `postgres:17-alpine` (major pinned to match Logto's v1.43.0 upstream Compose example).
- The Logto tag is an explicit patch version. PostgreSQL's official major tag receives patch updates. Before shared use, capture immutable platform-specific digests.
- Before upgrading, back up the LOCAL named volume, rehearse with a separate restored volume, and run the target version's official `logto db alteration deploy` command before starting the new server. Roll back the database backup together with the old image if schema changes are incompatible.

For this single local instance, official connectors ship with the pinned Logto image. Logto's shared connector-folder mount and `connector add --official` setup are documented for deployments that run multiple instances or explicitly install connectors; add that volume/init step if this local setup grows to that shape.

The pinned versions were checked against the [official v1.43.0 Compose file](https://github.com/logto-io/logto/blob/v1.43.0/docker-compose.yml), [Logto OSS upgrade guide](https://docs.logto.io/logto-oss/upgrading-oss-version), and [database alteration CLI guide](https://docs.logto.io/logto-oss/using-cli/database-alteration).

Detailed product/trust decisions are in [`docs/fireseed-identity-v1-development-spec.md`](../../docs/fireseed-identity-v1-development-spec.md); logging and changes are governed by [`docs/fireseed-identity-logging-change-protocol.md`](../../docs/fireseed-identity-logging-change-protocol.md).
