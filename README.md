# QuickNote Open ACI Reference Implementation

Status: **IMPLEMENTATION_CANDIDATE**

This project implements the Open ACI Minimum Implementation Profile for AI QuickNote (AI 随手记). It is a local-first, testable reference—not a production-ready mobile app and not a general AI agent.

The six implemented capabilities are:

- `aci.ai_quicknote.ledger.create`
- `aci.ai_quicknote.todo.create`
- `aci.ai_quicknote.memo.create`
- `aci.ai_quicknote.idea.create`
- `aci.ai_quicknote.record.get`
- `aci.ai_quicknote.record.search`

All entry points call one `CoreCapabilityLayer`. The SQLite repository, authorization policy, audit writer, and idempotency behavior are below that layer. Future UI, iOS App Intents, Android Intents, MCP, and test runners should be adapters only.

## What is implemented

- Four fixed modules: ledger (账目), todo (待办), memo (备忘), idea (灵感)
- Common `important` and `reminder` fields
- Local SQLite persistence
- Traceable raw input and confirmed record snapshots
- Actor identity, read/write actions, module-scoped grants, once/continuous duration
- Basic audit entries for allowed and denied calls
- Idempotent creates scoped to actor + capability + key
- Machine-readable manifest and JSON Schema 2020-12 input/output definitions
- A transport-neutral MCP 2026-07-28 adapter boundary for `server/discover`, `tools/list`, and `tools/call`
- Contract tests that use the same public adapter and core as future platform integrations

Not implemented: UI, share, update/delete, tag or time-range grants, sessions, delegation chains, confirmation tickets, cloud AI, OAuth, remote relay, notification delivery, or a network transport.

## Run tests

From this directory, using Python 3.11 or newer:

```text
python -m unittest discover -s tests -v
```

The tests create isolated temporary SQLite databases. They never write directly to the records table; setup grants are installed through the authorization administration surface, while capability behavior is exercised through `McpAdapter`.

## Minimal example

```python
from pathlib import Path
from quicknote_aci import Actor, CoreCapabilityLayer, McpAdapter

core = CoreCapabilityLayer(Path("quicknote.db"))
actor = Actor(subject="user-1", client_id="example.ai", client_name="Example AI")
core.permissions.grant(actor, actions={"write", "read"}, modules={"memo"}, duration="continuous")
adapter = McpAdapter(core)

response = adapter.call_tool(
    "aci.ai_quicknote.memo.create",
    {"content": "Passport is in the safe", "idempotency_key": "note-1"},
    actor,
)
```

See `docs/ACI-Minimum-Implementation-Profile.md` for normative scope and `docs/mobile-adapter-checklist.md` for the next iOS/Android work.

