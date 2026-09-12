# Open ACI Minimum Implementation Profile v0.1

Status: **IMPLEMENTATION_CANDIDATE**

This profile defines the smallest testable capability, permission, audit, and self-description contract for an AI-callable personal-record application. It does not define a transport protocol. Implementations map the contract onto MCP, iOS App Intents, Android Intents, or another platform-supported transport.

## Normative scope

An implementation MUST expose exactly four first-level data modules: `ledger` (账目), `todo` (待办), `memo` (备忘), and `idea` (灵感). `important` and `reminder` MUST have consistent meaning across all four. Search is a system-level operation over authorized modules; it does not own records. Share is deferred.

The minimum public capability set is `ledger.create`, `todo.create`, `memo.create`, `idea.create`, `record.get`, and `record.search`, using the fully qualified names in the manifest.

Every adapter MUST invoke the same Core Capability Layer. An adapter MUST NOT write records directly, bypass authorization, or synthesize a different actor identity.

Records MUST be local-first. The stored source input and the confirmed record snapshot MUST remain traceable by stable record ID. Public read results SHOULD return the confirmed record, not internal trace metadata.

## Permission profile

The minimum permission tuple is actor + action + module scope + duration.

- Actions: `read`, `write`
- Duration: `once`, `continuous`
- Modules: the four fixed modules

Permissions do not imply each other. A write grant does not permit reads. A multi-module search requires read permission for every requested module. A once grant is consumed by one successful authorized invocation. Tag constraints, time-range grants, session grants, modify/delete, delegation chains, confirmation tickets, resource-audience policy, and destructive-action policy are deferred.

## Actor and audit

The verified actor identity MUST include the user subject and calling client ID/name. Display-only model labels MUST NOT be used as authorization identity.

Each attempted public capability call MUST create an audit entry containing actor, capability, action, applicable module, time, result, error code when present, and affected record IDs. Denied calls MUST be audited without revealing record content.

## Idempotency

Create capabilities accept an optional `idempotency_key`. Repeating the same actor + capability + key MUST return the original record and MUST NOT create another record. The response identifies a replay.

## Self-description and schemas

The implementation MUST ship a machine-readable manifest. Every capability MUST provide JSON Schema 2020-12 input and output schemas with `additionalProperties: false` for request objects. Tool hints are descriptive only and MUST NOT replace server-side authorization.

## MCP 2026-07-28 mapping

MCP is an adapter, not part of ACI. A conforming adapter targets protocol version `2026-07-28`, does not depend on `initialize/initialized` or `Mcp-Session-Id`, can answer `server/discover`, and maps capability discovery/calls to `tools/list` and `tools/call`. A Streamable HTTP transport supplies `MCP-Protocol-Version`, `Mcp-Method`, and where applicable `Mcp-Name`; ACI does not redefine those headers or OAuth.

The reference implementation deliberately stops at a transport-neutral MCP mapping. Network exposure, OAuth, device relay, queueing, and mobile lifecycle behavior require separate platform threat modeling and testing.

## Conformance boundary

Conformance requires contract tests for create → get → search, denied access, module scope, idempotency, actor attribution, and audit output. Passing these tests supports only `IMPLEMENTATION_CANDIDATE`; production readiness additionally requires mobile integration, security review, migration/recovery tests, concurrency/load tests, privacy review, and real-device verification.

