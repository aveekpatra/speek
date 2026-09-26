"""Offline MCP fixture. Run with --http for HTTP/SSE or without arguments for stdio."""
import json
import base64
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def answer(message, modern=False):
    method = message.get("method")
    if "id" not in message:
        return None
    if method == "server/discover":
        if not modern:
            return {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Unsupported"}}
        result = {"resultType": "complete", "supportedVersions": ["2026-07-28"], "capabilities": {"tools": {}}}
    elif method == "initialize":
        result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "Fixture", "version": "1"}}
    elif method == "tools/list":
        result = {"tools": [{"name": "echo", "description": "Echo a value", "inputSchema": {"type": "object", "properties": {"value": {"type": "string"}}}, "annotations": {"readOnlyHint": True}}]}
    elif method == "tools/call":
        if modern and message["params"]["name"] == "needs-input":
            return {"jsonrpc": "2.0", "id": message["id"], "result": {"resultType": "input_required", "inputRequests": []}}
        if message["params"]["name"] == "hang":
            return None
        if message["params"]["name"] == "fail":
            return {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32000, "message": "secret-must-not-appear"}}
        value = message["params"]["arguments"].get("value", "")
        result = {"content": [{"type": "text", "text": value}], "structuredContent": {"echo": value}}
    else:
        result = {}
    if modern:
        result["resultType"] = "complete"
        if method == "tools/list":
            result["tools"][0]["inputSchema"]["properties"]["value"]["x-mcp-header"] = "Value"
    return {"jsonrpc": "2.0", "id": message["id"], "result": result}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        modern = self.path in ["/modern", "/unsupported"]
        if modern:
            meta = body.get("params", {}).get("_meta", {})
            assert meta.get("io.modelcontextprotocol/protocolVersion") == "2026-07-28"
            assert meta.get("io.modelcontextprotocol/clientCapabilities") == {}
            assert self.headers.get("MCP-Protocol-Version") == "2026-07-28"
            assert self.headers.get("Mcp-Method") == body["method"]
            assert self.headers.get("Mcp-Session-Id") is None
            assert self.headers.get("Authorization") == "Bearer fixture-secret"
            if body["method"] == "tools/call":
                assert self.headers.get("Mcp-Name") == body["params"]["name"]
                if body["params"]["name"] == "echo":
                    value = body["params"]["arguments"]["value"]
                    expected = "=?base64?" + base64.b64encode(value.encode()).decode() + "?="
                    assert self.headers.get("Mcp-Param-Value") == expected
        elif body["method"] != "initialize":
            if self.headers.get("Mcp-Session-Id") != "fixture-session" or self.headers.get("MCP-Protocol-Version") != "2025-06-18":
                self.send_response(400)
                self.end_headers()
                return
        if self.path == "/unsupported":
            encoded = json.dumps({"jsonrpc": "2.0", "id": body["id"], "error": {"code": -32022, "message": "Unsupported", "data": {"supported": ["2099-01-01"]}}}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return
        result = answer(body, modern)
        if result is None:
            self.send_response(202)
            self.end_headers()
            return
        stream = body["method"] == "tools/call"
        encoded = json.dumps(result).encode()
        if stream:
            encoded = b'event: message\ndata: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}\n\n' + b"event: message\ndata: " + encoded + b"\n\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream" if stream else "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        if not modern:
            self.send_header("Mcp-Session-Id", "fixture-session")
        self.end_headers()
        self.wfile.write(encoded)

    def do_DELETE(self):
        self.send_response(204)
        self.end_headers()


if "--http" in sys.argv:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()
else:
    for line in sys.stdin:
        try:
            message = json.loads(line)
            modern = "--modern" in sys.argv
            if modern and "id" in message:
                meta = message.get("params", {}).get("_meta", {})
                assert meta.get("io.modelcontextprotocol/protocolVersion") == "2026-07-28"
                assert meta.get("io.modelcontextprotocol/clientCapabilities") == {}
            response = answer(message, modern)
            if response is not None:
                print(json.dumps(response), flush=True)
        except (ValueError, KeyError):
            sys.exit(1)
