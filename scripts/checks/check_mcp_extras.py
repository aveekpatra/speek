#!/usr/bin/env python3
"""Server questions (elicitation), resources, and prompts over the production stdio transport."""
import pathlib, subprocess, tempfile, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
SERVER = r'''#!/usr/bin/env python3
import sys, json
def send(v): print(json.dumps(v), flush=True)
pending = None
for line in sys.stdin:
    m = json.loads(line); method = m.get("method"); mid = m.get("id")
    if method == "initialize":
        assert m["params"]["capabilities"]["elicitation"] is not None
        send({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{},"resources":{},"prompts":{}},"serverInfo":{"name":"fixture","version":"1"}}}); continue
    if method == "notifications/initialized": continue
    if method == "tools/call":
        pending = mid
        send({"jsonrpc":"2.0","id":"ask-1","method":"elicitation/create","params":{"message":"Which project?","requestedSchema":{"type":"object","properties":{"project":{"type":"string","title":"Project"}},"required":["project"]}}}); continue
    if mid == "ask-1" and method is None:
        answer = m["result"]["content"]["project"] if m["result"]["action"] == "accept" else "declined"
        send({"jsonrpc":"2.0","id":pending,"result":{"content":[{"type":"text","text":"Using " + answer}]}}); continue
    if method == "resources/list":
        send({"jsonrpc":"2.0","id":mid,"result":{"resources":[{"uri":"memo://roadmap","name":"Roadmap","mimeType":"text/plain"}]}}); continue
    if method == "resources/read":
        send({"jsonrpc":"2.0","id":mid,"result":{"contents":[{"uri":m["params"]["uri"],"text":"Q4: ship Speek"}]}}); continue
    if method == "prompts/get":
        send({"jsonrpc":"2.0","id":mid,"result":{"messages":[{"role":"user","content":{"type":"text","text":"Summarize " + m["params"]["arguments"]["topic"]}}]}}); continue
    send({"jsonrpc":"2.0","id":mid,"error":{"code":-32601,"message":"unknown"}})
'''
MAIN = '''import Foundation
@main struct Checks {
 static func main() async throws {
  let parsed = MCPElicitationCenter.parse(plugin: "Fixture", .object(["message": .string("Pick"), "requestedSchema": .object(["properties": .object([
      "count": .object(["type": .string("integer")]), "urgent": .object(["type": .string("boolean"), "default": .bool(true)]),
      "size": .object(["type": .string("string"), "enum": .array([.string("s"), .string("m")])])]), "required": .array([.string("count")])])]))!
  precondition(parsed.fields.count == 3 && parsed.fields.first { $0.id == "count" }?.required == true && parsed.fields.first { $0.id == "urgent" }?.defaultValue == "true")
  precondition(MCPElicitationCenter.parse(plugin: "F", .object(["mode": .string("url"), "url": .string("http://insecure")])) == nil, "non-HTTPS link accepted")
  let transport = try MCPStdioTransport(executable: CommandLine.arguments[2], arguments: [CommandLine.arguments[1]], workingDirectory: "", environment: [:])
  await transport.setServerRequestHandler { method, params in
    precondition(method == "elicitation/create" && params["message"]?.string == "Which project?")
    return .object(["action": .string("accept"), "content": .object(["project": .string("Speek")])])
  }
  _ = try await MCPProtocol.discover(transport, usingHTTP: false)
  let call = try await transport.request(method: "tools/call", params: .object(["name": .string("pick"), "arguments": .object([:])]))
  precondition(call["content"]?.array?.first?["text"]?.string == "Using Speek", "server question not answered")
  let resources = try await transport.request(method: "resources/list", params: .object([:]))
  precondition(resources["resources"]?.array?.first?["uri"]?.string == "memo://roadmap")
  let read = try await transport.request(method: "resources/read", params: .object(["uri": .string("memo://roadmap")]))
  precondition(read["contents"]?.array?.first?["text"]?.string == "Q4: ship Speek")
  let prompt = try await transport.request(method: "prompts/get", params: .object(["name": .string("sum"), "arguments": .object(["topic": .string("notes")])]))
  precondition(prompt["messages"]?.array?.first?["content"]?["text"]?.string == "Summarize notes")
  await transport.close()
  print("PASS: elicitation capability, form question answered mid-call, schema parsing, HTTPS-only links, resources list/read, prompts get")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='speek-mcp-extras-') as tmp:
    folder = pathlib.Path(tmp)
    (folder/'server.py').write_text(SERVER); (folder/'Main.swift').write_text(MAIN)
    sources = sorted(str(p) for p in (ROOT/'Speek/Integrations').glob('*.swift') if not p.name.endswith('View.swift'))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *sources, str(folder/'Main.swift'), '-o', str(folder/'check')], check=True)
    subprocess.run([str(folder/'check'), str(folder/'server.py'), sys.executable], check=True, timeout=60)
