# Fireseed Identity Logging and Change Protocol

Status: frozen for Phase 0 / Phase 1 local identity infrastructure.

## Logging policy

Identity infrastructure logs are operational diagnostics, not an audit store for credentials or app activity.

### Never log

- Passwords, one-time verification codes, password reset values.
- Access, refresh, or ID tokens; cookies; authorization headers.
- OAuth authorization codes, state values, provider access/refresh tokens, raw provider credentials.
- Client secrets, database passwords, signing/private keys, recovery secrets.
- Full callback/authorization URLs when they may contain any of the above.
- Private app/domain data or full request/response payloads.

### Permitted with minimization

- Environment (`local`), component, operation type, success/failure, sanitized error category, timestamp, and non-secret request/correlation ID.
- A non-sensitive internal user reference only where operational diagnosis requires it. Prefer a short-lived correlation ID; never use raw email as a log key.
- Container health, image version, database availability, and migration version.

### Debug and release behavior

- LOCAL debug may use Logto's normal container diagnostics, but must not add request-body/header dumps or print `.env` values.
- Future staging/production must use structured logs, least-privilege log access, defined retention, and secret redaction at source and collector. No debug token logging is allowed in any build.
- Security events may record event type, outcome, timestamp, environment, and sanitized user reference. Do not duplicate authentication factors or bearer credentials into an audit event.

## Change classification

1. **Documentation/config-only**: no persisted shape or authentication policy changes. Review diff, validate links/secret hygiene.
2. **Local operational change**: Compose, scripts, image pins, health checks. Verify disposable startup, health, restart persistence, and reset if Docker is available.
3. **Identity policy change**: sign-in identifiers, verification, account linking, session, deletion, or logging policy. Requires explicit security review, official behavior verification, and negative-path test evidence before implementation is enabled.
4. **Persistent schema/config migration**: Logto database alterations, issuer/subject or app owner mapping changes. Requires a database backup, migration rehearsal on a copy, compatibility check, rollback decision, and recorded before/after version.
5. **Application integration**: IdentityKit or any domain app adapter. Separate phase and separate review; no changes to app record semantics without a dedicated migration plan.

## Schema and configuration migration protocol

- Never edit Logto-owned database tables directly for app behavior.
- Keep local Compose secrets in ignored `.env`; commit only `.env.example` placeholders.
- Treat identity issuer, client ID, auth policy, and canonical subject semantics as security-sensitive config. Review and document each change.
- Before upgrading Logto or PostgreSQL, stop uncontrolled writes, back up the identity database, record exact image versions, and restore the backup into an isolated test copy.
- Run the official Logto CLI database alteration procedure for the target release against the copy first. Do not start a new server against an old schema when the release requires alterations.
- Confirm sign-in policy, OIDC discovery, Admin Console, and persistence smoke checks before replacing the active local image.

## Upgrade protocol

1. Read upstream release notes and current deployment/upgrade documentation.
2. Confirm target Logto and PostgreSQL versions and image digests for the local architecture.
3. Back up the named local volume to a protected local path; never commit the backup.
4. Restore to an isolated volume and run the official alteration command using the new Logto CLI.
5. Verify health, OIDC discovery, Admin Console, and restart persistence on the copy.
6. Update the pinned version and this protocol/spec with the migration and known behavior changes.
7. Retain the prior image tag and database backup until validation succeeds.

## Rollback protocol

- Stop the Logto containers before restore.
- If the target release altered schema, restore the pre-upgrade database backup rather than only rolling the image backward.
- Restore only the named LOCAL identity database volume. Never point rollback commands at any future staging/production store.
- Re-run health/discovery smoke checks after restore. Record failure category and versions without exposing secrets.

## Incident notes

For a suspected identity/security issue, record UTC time, environment, affected image/config revision, sanitized operation and outcome, scope, and containment/recovery steps. Preserve relevant logs with restricted access. Do not paste tokens, codes, provider credentials, raw authorization URLs, or full private identity payloads into issues or chat. If a credential may have been exposed, revoke/rotate it through its owner system and document the revocation result without reproducing the secret.

## Review rule

Any behavior that could merge accounts, alter the canonical subject, remove the final sign-in route, expose a session, or delete identity data is a security/persistent-data change and cannot be treated as a routine configuration tweak.
