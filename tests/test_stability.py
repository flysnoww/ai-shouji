import sqlite3
import tempfile
import unittest
from pathlib import Path

from quicknote_aci import Actor, CoreCapabilityLayer, McpAdapter
from quicknote_aci.errors import ValidationError


class OwnershipRegressionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "records.db"
        self.core = CoreCapabilityLayer(self.path)
        self.adapter = McpAdapter(self.core)
        self.a = Actor("owner-a", "client", "Test")
        self.b = Actor("owner-b", "client", "Test")
        for actor in (self.a, self.b):
            self.core.permissions.grant(actor, actions={"read", "write"}, modules={"memo", "idea", "todo", "ledger"}, duration="continuous")

    def tearDown(self):
        self.core.close()
        self.tmp.cleanup()

    def call(self, capability, args, actor=None):
        return self.adapter.call_tool(capability, args, actor or self.a)["structuredContent"]

    def test_get_search_and_reopen_enforce_owner(self):
        created = self.call("aci.ai_quicknote.memo.create", {"content": "A private", "idempotency_key": "one"})
        record_id = created["result"]["record"]["id"]
        self.assertFalse(self.call("aci.ai_quicknote.record.get", {"record_id": record_id}, self.b)["ok"])
        self.assertEqual(self.call("aci.ai_quicknote.record.search", {}, self.b)["result"]["count"], 0)
        self.core.close()
        self.core = CoreCapabilityLayer(self.path)
        self.adapter = McpAdapter(self.core)
        self.assertTrue(self.call("aci.ai_quicknote.record.get", {"record_id": record_id})["ok"])
        self.assertFalse(self.call("aci.ai_quicknote.record.get", {"record_id": record_id}, self.b)["ok"])
        self.assertTrue(self.call("aci.ai_quicknote.memo.create", {"content": "A private", "idempotency_key": "one"})["result"]["idempotent_replay"])

    def test_malformed_inputs_are_validation_errors_and_next_save_works(self):
        for capability, args in [
            ("memo.create", []), ("record.search", {"modules": [{}]}),
            ("ledger.create", {"content": "bad", "amount": 12}),
            ("ledger.create", {"content": "bad", "currency": "usd"}),
            ("todo.create", {"content": "bad", "completed": "true"}),
            ("todo.create", {"content": "bad", "due_at": "2026-10-03"}),
            ("memo.create", {"content": "bad", "raw_input": float("nan")}),
        ]:
            with self.subTest(args=args):
                result = self.call("aci.ai_quicknote." + capability, args)
                self.assertFalse(result["ok"])
                self.assertEqual(result["error"]["code"], "ACI_INVALID_INPUT")
        self.assertTrue(self.call("aci.ai_quicknote.memo.create", {"content": "still works"})["ok"])

    def test_grant_key_separator_cannot_alias_another_actor(self):
        with self.assertRaises(ValidationError):
            self.core.permissions.grant(Actor("a|b", "c", "Test"), actions={"read"}, modules={"memo"}, duration="continuous")

    def test_legacy_rows_remain_on_disk_without_ownership_adoption(self):
        record_id = self.call("aci.ai_quicknote.memo.create", {"content": "legacy"})["result"]["record"]["id"]
        self.core.close()
        with sqlite3.connect(self.path) as db:
            db.execute("ALTER TABLE records DROP COLUMN owner_subject")
        db.close()
        self.core = CoreCapabilityLayer(self.path)
        self.adapter = McpAdapter(self.core)
        self.assertEqual(self.call("aci.ai_quicknote.record.search", {})["result"]["count"], 0)
        self.assertFalse(self.call("aci.ai_quicknote.record.get", {"record_id": record_id})["ok"])
        self.assertEqual(self.core.get_trace(record_id)["confirmed_record"]["content"], "legacy")
