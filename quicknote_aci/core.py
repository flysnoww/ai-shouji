from __future__ import annotations

import json
import re
import sqlite3
import threading
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .errors import ACIError, NotFoundError, UnauthorizedError, ValidationError

MODULES = {"ledger", "todo", "memo", "idea"}
CREATE_CAPABILITIES = {f"aci.ai_quicknote.{module}.create": module for module in MODULES}
GET_CAPABILITY = "aci.ai_quicknote.record.get"
SEARCH_CAPABILITY = "aci.ai_quicknote.record.search"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


@dataclass(frozen=True)
class Actor:
    subject: str
    client_id: str
    client_name: str
    client_version: str = "0.0.0"
    platform: str = "local"

    @property
    def key(self) -> str:
        return f"{self.subject}|{self.client_id}"


class PermissionAdmin:
    """Grant administration is deliberately separate from public capabilities."""

    def __init__(self, core: "CoreCapabilityLayer"):
        self._core = core

    def grant(self, actor: Actor, *, actions: set[str], modules: set[str], duration: str) -> str:
        self._core._validate_actor(actor)
        if not actions or not actions <= {"read", "write"}:
            raise ValueError("actions must contain only read/write")
        if not modules or not modules <= MODULES:
            raise ValueError("modules must be a non-empty subset of fixed modules")
        if duration not in {"once", "continuous"}:
            raise ValueError("duration must be once or continuous")
        grant_id = _id("grt")
        with self._core._transaction() as db:
            db.execute(
                "INSERT INTO grants VALUES (?, ?, ?, ?, ?, ?, NULL)",
                (grant_id, actor.key, json.dumps(sorted(actions)), json.dumps(sorted(modules)), duration, _now()),
            )
        return grant_id


class _Transaction:
    def __init__(self, core: "CoreCapabilityLayer"):
        self.core = core

    def __enter__(self):
        self.core._lock.acquire()
        try:
            self.core._db.execute("BEGIN IMMEDIATE")
        except BaseException:
            self.core._lock.release()
            raise
        return self.core._db

    def __exit__(self, exc_type, exc, tb):
        try:
            self.core._db.execute("ROLLBACK" if exc_type else "COMMIT")
        except BaseException:
            self.core._db.rollback()
            raise
        finally:
            self.core._lock.release()


class CoreCapabilityLayer:
    def __init__(self, database: str | Path = ":memory:"):
        self._db = sqlite3.connect(str(database), check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        self._init_schema()
        self.permissions = PermissionAdmin(self)

    def close(self) -> None:
        self._db.close()

    def _transaction(self) -> _Transaction:
        return _Transaction(self)

    def _init_schema(self) -> None:
        self._db.executescript("""
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS records (
          id TEXT PRIMARY KEY, module TEXT NOT NULL, content TEXT NOT NULL,
          important INTEGER NOT NULL, reminder_json TEXT, module_data_json TEXT NOT NULL,
          raw_input_json TEXT NOT NULL, confirmed_record_json TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, revision INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS grants (
          id TEXT PRIMARY KEY, actor_key TEXT NOT NULL, actions_json TEXT NOT NULL,
          modules_json TEXT NOT NULL, duration TEXT NOT NULL, created_at TEXT NOT NULL,
          consumed_at TEXT
        );
        CREATE TABLE IF NOT EXISTS idempotency (
          actor_key TEXT NOT NULL, capability TEXT NOT NULL, idem_key TEXT NOT NULL,
          record_id TEXT NOT NULL, PRIMARY KEY(actor_key, capability, idem_key)
        );
        CREATE TABLE IF NOT EXISTS audit (
          id TEXT PRIMARY KEY, request_id TEXT NOT NULL, actor_json TEXT NOT NULL,
          capability TEXT NOT NULL, action TEXT NOT NULL, module TEXT,
          result TEXT NOT NULL, error_code TEXT, record_ids_json TEXT NOT NULL,
          occurred_at TEXT NOT NULL
        );
        """)
        # Legacy rows have no proven owner. Retain them without assigning ownership.
        columns = {row["name"] for row in self._db.execute("PRAGMA table_info(records)")}
        if "owner_subject" not in columns:
            self._db.execute("ALTER TABLE records ADD COLUMN owner_subject TEXT")
        self._db.commit()

    def invoke(self, capability: str, arguments: dict[str, Any], actor: Actor, *, request_id: str | None = None) -> dict:
        request_id = request_id or _id("req")
        audit_id = _id("aud")
        action, module = "read", None
        try:
            self._validate_actor(actor)
            if not isinstance(arguments, dict) or not isinstance(capability, str):
                raise ValidationError("Capability and arguments must be a string and object")
            if not all(isinstance(key, str) for key in arguments):
                raise ValidationError("Input property names must be strings")
            with self._transaction() as db:
                action, module = self._classify(capability, arguments, actor)
                grant_id = self._authorize(db, actor, action, module)
                if capability in CREATE_CAPABILITIES:
                    result, audit_result = self._create(db, capability, module, arguments, actor)
                elif capability == GET_CAPABILITY:
                    result, audit_result = self._get(db, arguments, module, actor)
                elif capability == SEARCH_CAPABILITY:
                    result, audit_result = self._search(db, arguments, actor)
                else:
                    raise ValidationError("Unknown capability", details={"capability": capability})
                self._consume_once(db, grant_id)
                record_ids = self._record_ids(result)
                self._audit(db, audit_id, request_id, actor, capability, action, module, audit_result, None, record_ids)
            return {"ok": True, "request_id": request_id, "result": result, "warnings": [], "audit_id": audit_id}
        except ACIError as exc:
            with self._transaction() as db:
                self._audit(db, audit_id, request_id, actor, capability, action, module, "denied" if isinstance(exc, UnauthorizedError) else "error", exc.code, [])
            return {"ok": False, "request_id": request_id, "error": {"code": exc.code, "message": exc.message, "details": exc.details, "retryable": exc.retryable}, "audit_id": audit_id}

    def _classify(self, capability: str, arguments: dict, actor: Actor) -> tuple[str, str | None]:
        if capability in CREATE_CAPABILITIES:
            return "write", CREATE_CAPABILITIES[capability]
        if capability == GET_CAPABILITY:
            record_id = arguments.get("record_id")
            row = self._db.execute("SELECT module FROM records WHERE id = ? AND owner_subject = ?", (record_id, actor.subject)).fetchone() if isinstance(record_id, str) else None
            return "read", row["module"] if row else None
        if capability == SEARCH_CAPABILITY:
            modules = arguments.get("modules")
            if "modules" in arguments and (not isinstance(modules, list) or not modules or not all(isinstance(value, str) and value in MODULES for value in modules)):
                raise ValidationError("modules must contain valid module names")
            return "read", modules[0] if isinstance(modules, list) and len(modules) == 1 else None
        return "read", None

    @staticmethod
    def _validate_actor(actor: Actor) -> None:
        if any(not isinstance(value, str) or not value.strip() for value in (actor.subject, actor.client_id, actor.client_name)):
            raise ValidationError("Actor subject, client_id, and client_name are required")
        if "|" in actor.subject or "|" in actor.client_id:
            raise ValidationError("Actor subject and client_id must not contain the grant-key separator")

    def _authorize(self, db, actor: Actor, action: str, module: str | None) -> str:
        rows = db.execute("SELECT * FROM grants WHERE actor_key = ? AND consumed_at IS NULL", (actor.key,)).fetchall()
        for row in rows:
            actions, modules = set(json.loads(row["actions_json"])), set(json.loads(row["modules_json"]))
            requested_modules = MODULES if module is None else {module}
            if action in actions and requested_modules <= modules:
                return row["id"]
        raise UnauthorizedError("No active grant covers this action and module scope", details={"action": action, "module": module})

    @staticmethod
    def _consume_once(db, grant_id: str) -> None:
        db.execute("UPDATE grants SET consumed_at = ? WHERE id = ? AND duration = 'once'", (_now(), grant_id))

    def _create(self, db, capability: str, module: str, args: dict, actor: Actor) -> tuple[dict, str]:
        self._validate_create(args, module)
        idem = args.get("idempotency_key")
        if idem:
            existing = db.execute("SELECT record_id FROM idempotency WHERE actor_key=? AND capability=? AND idem_key=?", (actor.key, capability, idem)).fetchone()
            if existing:
                return {"record": self._load_record(db, existing["record_id"], actor.subject), "idempotent_replay": True}, "idempotent_replay"
        timestamp, record_id = _now(), _id("rec")
        module_data = {k: args[k] for k in ("amount", "currency", "due_at", "completed") if k in args}
        record = {"id": record_id, "module": module, "content": args["content"], "important": args.get("important", False), "reminder": args.get("reminder"), "module_data": module_data, "created_at": timestamp, "updated_at": timestamp, "revision": 1}
        raw_input = args.get("raw_input", args["content"])
        db.execute("INSERT INTO records (id,module,content,important,reminder_json,module_data_json,raw_input_json,confirmed_record_json,created_at,updated_at,revision,owner_subject) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (record_id, module, record["content"], int(record["important"]), json.dumps(record["reminder"]), json.dumps(module_data), json.dumps(raw_input, ensure_ascii=False), json.dumps(record, ensure_ascii=False), timestamp, timestamp, 1, actor.subject))
        if idem:
            db.execute("INSERT INTO idempotency VALUES (?, ?, ?, ?)", (actor.key, capability, idem, record_id))
        return {"record": record, "idempotent_replay": False}, "success"

    @staticmethod
    def _validate_create(args: dict, module: str) -> None:
        allowed = {"content", "important", "reminder", "raw_input", "idempotency_key"}
        if module == "ledger": allowed |= {"amount", "currency"}
        if module == "todo": allowed |= {"due_at", "completed"}
        unknown = set(args) - allowed
        if unknown:
            raise ValidationError("Unknown input properties", details={"properties": sorted(unknown)})
        if not isinstance(args.get("content"), str) or not args["content"].strip() or len(args["content"]) > 10000:
            raise ValidationError("content must be a non-empty string up to 10000 characters")
        if "important" in args and not isinstance(args["important"], bool):
            raise ValidationError("important must be boolean")
        if "reminder" in args and args["reminder"] is not None and not isinstance(args["reminder"], dict):
            raise ValidationError("reminder must be an object or null")
        if "idempotency_key" in args and (not isinstance(args["idempotency_key"], str) or not 1 <= len(args["idempotency_key"]) <= 200):
            raise ValidationError("idempotency_key must contain 1 to 200 characters")
        for field, pattern in (("amount", r"-?[0-9]+(\.[0-9]+)?"), ("currency", r"[A-Z]{3}")):
            if field in args and (not isinstance(args[field], str) or re.fullmatch(pattern, args[field]) is None):
                raise ValidationError(f"{field} has invalid format")
        if "completed" in args and not isinstance(args["completed"], bool):
            raise ValidationError("completed must be boolean")
        if args.get("due_at") is not None:
            try:
                if not isinstance(args["due_at"], str) or datetime.fromisoformat(args["due_at"].replace("Z", "+00:00")).tzinfo is None:
                    raise ValueError()
            except (ValueError, TypeError):
                raise ValidationError("due_at must be an ISO date-time with timezone")
        try:
            json.dumps(args, allow_nan=False)
        except (TypeError, ValueError):
            raise ValidationError("Input must contain finite JSON values")

    def _get(self, db, args: dict, module: str | None, actor: Actor) -> tuple[dict, str]:
        if set(args) != {"record_id"} or not isinstance(args.get("record_id"), str):
            raise ValidationError("record.get requires only record_id")
        if module is None:
            raise NotFoundError("Record not found")
        return {"record": self._load_record(db, args["record_id"], actor.subject)}, "success"

    def _search(self, db, args: dict, actor: Actor) -> tuple[dict, str]:
        allowed = {"query", "modules", "important", "limit"}
        if set(args) - allowed:
            raise ValidationError("Unknown search properties", details={"properties": sorted(set(args) - allowed)})
        query = args.get("query", "")
        modules = args.get("modules", sorted(MODULES))
        limit = args.get("limit", 50)
        if not isinstance(query, str) or not isinstance(modules, list) or not modules or not all(isinstance(module, str) and module in MODULES for module in modules):
            raise ValidationError("query/modules are invalid")
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 100:
            raise ValidationError("limit must be an integer from 1 to 100")
        sql = f"SELECT id FROM records WHERE owner_subject = ? AND module IN ({','.join('?' for _ in modules)}) AND content LIKE ?"
        params: list[Any] = [actor.subject] + list(modules) + [f"%{query}%"]
        if "important" in args:
            if not isinstance(args["important"], bool):
                raise ValidationError("important must be boolean")
            sql += " AND important = ?"
            params.append(int(args["important"]))
        sql += " ORDER BY created_at DESC, id ASC LIMIT ?"
        params.append(limit)
        records = [self._load_record(db, row["id"], actor.subject) for row in db.execute(sql, params).fetchall()]
        return {"records": records, "count": len(records)}, "success"

    @staticmethod
    def _load_record(db, record_id: str, owner_subject: str) -> dict:
        row = db.execute("SELECT confirmed_record_json FROM records WHERE id = ? AND owner_subject = ?", (record_id, owner_subject)).fetchone()
        if not row:
            raise NotFoundError("Record not found")
        return json.loads(row["confirmed_record_json"])

    @staticmethod
    def _record_ids(result: dict) -> list[str]:
        if "record" in result:
            return [result["record"]["id"]]
        return [record["id"] for record in result.get("records", [])]

    @staticmethod
    def _audit(db, audit_id, request_id, actor, capability, action, module, result, error_code, record_ids):
        db.execute("INSERT INTO audit VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (audit_id, request_id, json.dumps(asdict(actor), ensure_ascii=False), capability, action, module, result, error_code, json.dumps(record_ids), _now()))

    def get_audit(self, audit_id: str) -> dict | None:
        row = self._db.execute("SELECT * FROM audit WHERE id = ?", (audit_id,)).fetchone()
        if not row:
            return None
        result = dict(row)
        result["actor"] = json.loads(result.pop("actor_json"))
        result["record_ids"] = json.loads(result.pop("record_ids_json"))
        return result

    def get_trace(self, record_id: str) -> dict | None:
        row = self._db.execute("SELECT raw_input_json, confirmed_record_json FROM records WHERE id = ?", (record_id,)).fetchone()
        return {"raw_input": json.loads(row["raw_input_json"]), "confirmed_record": json.loads(row["confirmed_record_json"])} if row else None
