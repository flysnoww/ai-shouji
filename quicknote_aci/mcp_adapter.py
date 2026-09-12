from __future__ import annotations

import json
from pathlib import Path

from .core import Actor, CoreCapabilityLayer

PROTOCOL_VERSION = "2026-07-28"


class McpAdapter:
    """Transport-neutral mapping to MCP 2026-07-28; it does not invent a transport."""

    def __init__(self, core: CoreCapabilityLayer):
        self.core = core
        root = Path(__file__).resolve().parents[1]
        self.manifest = json.loads((root / "manifest" / "aci-manifest.json").read_text(encoding="utf-8"))

    def discover(self) -> dict:
        return {"protocolVersions": [PROTOCOL_VERSION], "capabilities": {"tools": {"listChanged": False}}, "_meta": {"io.modelcontextprotocol/serverInfo": {"name": "quicknote-aci-reference", "version": "0.1.0"}}}

    def list_tools(self) -> list[dict]:
        root = Path(__file__).resolve().parents[1]
        tools = []
        for cap in self.manifest["capabilities"]:
            tools.append({"name": cap["name"], "title": cap["title"], "description": cap["description"], "inputSchema": json.loads((root / cap["inputSchema"]).read_text(encoding="utf-8")), "outputSchema": json.loads((root / cap["outputSchema"]).read_text(encoding="utf-8")), "annotations": cap["annotations"]})
        return tools

    def call_tool(self, name: str, arguments: dict, actor: Actor, *, request_id: str | None = None) -> dict:
        envelope = self.core.invoke(name, arguments, actor, request_id=request_id)
        return {"content": [{"type": "text", "text": "ok" if envelope["ok"] else envelope["error"]["message"]}], "structuredContent": envelope, "isError": not envelope["ok"]}

    def dispatch(self, request: dict, actor: Actor) -> dict:
        method = request.get("method")
        request_id = request.get("id")
        if method == "server/discover":
            result = self.discover()
        elif method == "tools/list":
            result = {"tools": self.list_tools()}
        elif method == "tools/call":
            params = request.get("params", {})
            result = self.call_tool(params.get("name", ""), params.get("arguments", {}), actor, request_id=str(request_id))
        else:
            return {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32601, "message": "Method not found"}}
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

