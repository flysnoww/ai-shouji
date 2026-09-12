import json
import tempfile
import unittest
from pathlib import Path

from quicknote_aci import Actor, CoreCapabilityLayer, McpAdapter


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.core = CoreCapabilityLayer(Path(self.tmp.name) / "test.db")
        self.adapter = McpAdapter(self.core)
        self.actor = Actor("user-1", "test.runner", "Contract Test Runner", "0.1.0", "test")

    def tearDown(self):
        self.core.close()
        self.tmp.cleanup()

    def grant(self, actions, modules, duration="continuous"):
        return self.core.permissions.grant(self.actor, actions=set(actions), modules=set(modules), duration=duration)

    def call(self, name, args):
        return self.adapter.call_tool(name, args, self.actor)["structuredContent"]

    def test_create_get_search_and_trace(self):
        self.grant({"write", "read"}, {"ledger", "todo", "memo", "idea"})
        for module in ("ledger", "todo", "memo", "idea"):
            created = self.call(f"aci.ai_quicknote.{module}.create", {"content": f"needle {module}", "important": True, "raw_input": {"utterance": f"raw {module}"}})
            self.assertTrue(created["ok"])
            record_id = created["result"]["record"]["id"]
            fetched = self.call("aci.ai_quicknote.record.get", {"record_id": record_id})
            self.assertEqual(module, fetched["result"]["record"]["module"])
            trace = self.core.get_trace(record_id)
            self.assertEqual(f"raw {module}", trace["raw_input"]["utterance"])
            self.assertEqual(record_id, trace["confirmed_record"]["id"])
        found = self.call("aci.ai_quicknote.record.search", {"query": "needle", "modules": ["ledger", "todo", "memo", "idea"]})
        self.assertEqual(4, found["result"]["count"])

    def test_unauthorized_access_is_denied_and_audited(self):
        denied = self.call("aci.ai_quicknote.memo.create", {"content": "secret"})
        self.assertFalse(denied["ok"])
        self.assertEqual("ACI_UNAUTHORIZED", denied["error"]["code"])
        audit = self.core.get_audit(denied["audit_id"])
        self.assertEqual("denied", audit["result"])
        self.assertEqual([], audit["record_ids"])

    def test_module_scope_blocks_other_module_and_multimodule_search(self):
        self.grant({"write", "read"}, {"memo"})
        self.assertTrue(self.call("aci.ai_quicknote.memo.create", {"content": "allowed"})["ok"])
        blocked = self.call("aci.ai_quicknote.idea.create", {"content": "blocked"})
        self.assertEqual("ACI_UNAUTHORIZED", blocked["error"]["code"])
        blocked_search = self.call("aci.ai_quicknote.record.search", {"query": "", "modules": ["memo", "idea"]})
        self.assertEqual("ACI_UNAUTHORIZED", blocked_search["error"]["code"])

    def test_idempotency_is_actor_and_capability_scoped(self):
        self.grant({"write"}, {"memo"})
        one = self.call("aci.ai_quicknote.memo.create", {"content": "once", "idempotency_key": "same"})
        two = self.call("aci.ai_quicknote.memo.create", {"content": "ignored", "idempotency_key": "same"})
        self.assertEqual(one["result"]["record"]["id"], two["result"]["record"]["id"])
        self.assertTrue(two["result"]["idempotent_replay"])

    def test_once_grant_and_actor_audit(self):
        self.grant({"write"}, {"todo"}, duration="once")
        first = self.call("aci.ai_quicknote.todo.create", {"content": "first"})
        second = self.call("aci.ai_quicknote.todo.create", {"content": "second"})
        self.assertTrue(first["ok"])
        self.assertEqual("ACI_UNAUTHORIZED", second["error"]["code"])
        audit = self.core.get_audit(first["audit_id"])
        self.assertEqual("test.runner", audit["actor"]["client_id"])
        self.assertEqual("write", audit["action"])
        self.assertEqual("todo", audit["module"])

    def test_manifest_and_mcp_self_description(self):
        manifest = self.adapter.manifest
        self.assertEqual("IMPLEMENTATION_CANDIDATE", manifest["status"])
        self.assertEqual(6, len(manifest["capabilities"]))
        self.assertEqual(["2026-07-28"], self.adapter.discover()["protocolVersions"])
        self.assertEqual(6, len(self.adapter.list_tools()))
        for path in (Path(__file__).parents[1] / "schemas").glob("*.json"):
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual("https://json-schema.org/draft/2020-12/schema", data["$schema"])


if __name__ == "__main__":
    unittest.main()

