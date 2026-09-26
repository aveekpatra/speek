import Foundation

@main struct TransportChecks {
    static func main() async throws {
        let fixture = CommandLine.arguments[1]
        let port = CommandLine.arguments[2]
        let remote = MCPHTTPTransport(endpoint: URL(string: "http://127.0.0.1:" + port + "/mcp")!)
        try await check(remote)
        await remote.close()
        let local = try MCPStdioTransport(executable: "/usr/bin/python3", arguments: [fixture], workingDirectory: "", environment: [:])
        try await check(local)
        let pending = Task { try await local.request(method: "tools/call", params: .object(["name": .string("hang"), "arguments": .object([:])])) }
        try await Task.sleep(nanoseconds: 50_000_000)
        pending.cancel()
        do { _ = try await pending.value; fatalError("Cancellation was ignored") }
        catch is CancellationError {}
        await local.close()
        do { _ = try await local.request(method: "tools/list", params: .object([:])); fatalError("Closed transport accepted request") }
        catch MCPError.disconnected {}
        let modernHTTP = MCPHTTPTransport(endpoint: URL(string: "http://127.0.0.1:" + port + "/modern")!, token: "fixture-secret")
        try await checkModern(modernHTTP, usingHTTP: true)
        await modernHTTP.close()
        let modernLocal = try MCPStdioTransport(executable: "/usr/bin/python3", arguments: [fixture, "--modern"], workingDirectory: "", environment: [:])
        try await checkModern(modernLocal, usingHTTP: false)
        await modernLocal.close()
        let fallbackHTTP = MCPHTTPTransport(endpoint: URL(string: "http://127.0.0.1:" + port + "/mcp")!)
        let legacyDiscovery = try await MCPProtocol.discover(fallbackHTTP, usingHTTP: true)
        precondition(legacyDiscovery["protocolVersion"]?.string == "2025-06-18")
        await fallbackHTTP.close()
        let fallbackStdio = try MCPStdioTransport(executable: "/usr/bin/python3", arguments: [fixture], workingDirectory: "", environment: [:])
        let stdioLegacy = try await MCPProtocol.discover(fallbackStdio, usingHTTP: false)
        precondition(stdioLegacy["protocolVersion"]?.string == "2025-06-18")
        await fallbackStdio.close()
        let unsupported = MCPHTTPTransport(endpoint: URL(string: "http://127.0.0.1:" + port + "/unsupported")!, token: "fixture-secret")
        do { _ = try await MCPProtocol.discover(unsupported, usingHTTP: true); fatalError("Unknown version accepted") }
        catch MCPError.unsupportedVersion(let versions) { precondition(versions == ["2099-01-01"]) }
        await unsupported.close()
        try await checkStorage()
        print("PASS: 2026 metadata/auth/custom headers, HTTP+stdio generation fallback, unsupported versions, input-required rejection, JSON/SSE, cancellation, persistence, skills, disabled tools")
    }
    static func check(_ transport: any MCPTransport) async throws {
        let initialized = try await transport.request(method: "initialize", params: .object([:]))
        precondition(initialized["protocolVersion"]?.string == "2025-06-18")
        try await transport.notify(method: "notifications/initialized", params: .object([:]))
        let tools = try await transport.request(method: "tools/list", params: .object([:]))
        precondition(tools["tools"]?.array?.first?["name"]?.string == "echo")
        let answer = try await transport.request(method: "tools/call", params: .object(["name": .string("echo"), "arguments": .object(["value": .string("hello")])]))
        precondition(answer["content"]?.array?.first?["text"]?.string == "hello")
        do {
            _ = try await transport.request(method: "tools/call", params: .object(["name": .string("fail"), "arguments": .object([:])]))
            fatalError("RPC error accepted")
        } catch MCPError.server(let code) { precondition(code == -32000) }
    }
    static func checkModern(_ transport: any MCPTransport, usingHTTP: Bool) async throws {
        let discovery = try await MCPProtocol.discover(transport, usingHTTP: usingHTTP)
        precondition(discovery["supportedVersions"]?.array?.first?.string == "2026-07-28")
        let result = try await transport.request(method: "tools/list", params: .object([:]))
        let schema = result["tools"]?.array?.first?["inputSchema"] ?? .null
        try await transport.setToolSchemas([IntegrationTool(pluginID: UUID(), name: "echo", title: "Echo", description: "", inputSchema: schema, readOnly: true)])
        let value = " leading and trailing \n"
        let called = try await transport.request(method: "tools/call", params: .object(["name": .string("echo"), "arguments": .object(["value": .string(value)])]))
        precondition(called["content"]?.array?.first?["text"]?.string == value)
        do {
            _ = try await transport.request(method: "tools/call", params: .object(["name": .string("needs-input"), "arguments": .object([:])]))
            fatalError("Unsupported interactive result was accepted")
        } catch MCPError.capabilityRequired {}
        precondition(MCPProtocol.headerValue("=?base64?literal?=").hasPrefix("=?base64?PT9"))
    }
    @MainActor static func checkStorage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("speek-mcp-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IntegrationStore(directory: directory)
        let plugin = MCPPlugin(name: "Fixture", endpoint: "http://127.0.0.1/mcp")
        try store.save(plugin)
        let reload = IntegrationStore(directory: directory)
        precondition(reload.plugins.count == 1 && reload.plugins[0].name == "Fixture")
        let source = directory.appendingPathComponent("SKILL.md")
        try "---\nname: Calendar\ndescription: Calendar planning\n---\nCheck dates before creating meetings.".write(to: source, atomically: true, encoding: .utf8)
        try store.importSkill(from: source)
        precondition(store.enabledSkillInstructions(for: "Calendar meeting").contains("Check dates"))
        try store.setSkillEnabled(id: store.skills[0].id, enabled: false)
        precondition(store.enabledSkillInstructions(for: "Calendar meeting").isEmpty)
        let tool = IntegrationTool(pluginID: plugin.id, name: "echo", title: "Echo", description: "", inputSchema: .object([:]), readOnly: true)
        try store.setToolEnabled(tool, enabled: false)
        precondition(store.plugins[0].disabledTools.contains("echo"))
        var invalid = plugin
        invalid.endpoint = "http://example.com/mcp"
        do { try store.save(invalid); fatalError("Insecure endpoint accepted") } catch MCPError.invalidConfiguration {}
    }
}
