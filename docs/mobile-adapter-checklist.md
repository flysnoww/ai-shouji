# iOS and Android Adapter Checklist

Status: **IMPLEMENTATION_CANDIDATE**

## Shared adapter rules

- Map platform actions to the six manifest capabilities without duplicating business logic.
- Construct actor identity from verified platform/app credentials, not request text.
- Route every call through the Core Capability Layer.
- Keep raw input and confirmed records traceable on device.
- Surface permission denial and audit IDs without leaking unauthorized content.
- Add migration, concurrency, cancellation, background-lifecycle, and recovery tests.
- Keep share, update/delete, cloud agent behavior, and advanced grants out of this phase.

## iOS

- Define App Intents for four creates, get, and search.
- Define AppEntity/AppEnum mappings for records and fixed modules.
- Map system authorization UI to read/write, module scope, and once/continuous grants.
- Verify foreground/background execution limits and data-protection behavior on real devices.
- Test Spotlight/Siri/Shortcuts invocation and actor attribution separately.
- Use an app-group or other Apple-supported local boundary only after threat modeling.

## Android

- Define explicit Intents or App Actions for the same six capabilities.
- Use stable record/module entities and validated extras/parameters.
- Map Android identity and permission UX to the same grant tuple.
- Verify exported-component rules, signature protection, background limits, and process death.
- Test Assistant/shortcut invocation and actor attribution separately.
- Keep local IPC explicit; do not expose an unauthenticated generic endpoint.

## MCP and remote follow-up

- Select an official 2026-07-28 SDK and pin the protocol version explicitly.
- Add Streamable HTTP only if remote invocation is required; preserve required MCP headers.
- Design OAuth/resource-server metadata and relay/device wake-up independently of ACI.
- Never treat the phone as an always-on inbound server by assumption.
- Add remote revocation, replay protection, offline queue policy, and privacy threat tests.

