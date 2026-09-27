import Foundation

indirect enum MCPValue: Codable, Equatable, Sendable {
    case object([String: MCPValue]), array([MCPValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: MCPValue].self) { self = .object(value) }
        else { self = .array(try container.decode([MCPValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(_ key: String) -> MCPValue? {
        guard case .object(let value) = self else { return nil }
        return value[key]
    }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var array: [MCPValue]? { if case .array(let value) = self { return value }; return nil }
    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    var object: [String: MCPValue]? { if case .object(let value) = self { return value }; return nil }
    var jsonString: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "null" }
}

struct MCPPlugin: Codable, Identifiable, Equatable, Sendable {
    enum Transport: String, Codable, CaseIterable, Identifiable {
        case http, stdio
        var id: String { rawValue }
        var title: String { self == .http ? "Remote server" : "Local server" }
    }
    var id: UUID = UUID()
    var name: String
    var transport: Transport = .http
    var endpoint: String = ""
    var executable: String = ""
    var arguments: [String] = []
    var workingDirectory: String = ""
    var enabled = false
    var disabledTools: Set<String> = []
    /// Set when the plugin was added from the directory; used for its logo.
    var directoryID: String?
    /// A command whose output is the bearer token, run in the login shell at connect time
    /// (for example `gh auth token`), so Speek never keeps its own copy.
    var tokenCommand: String?
    /// A pre-registered OAuth client for servers that do not allow dynamic registration.
    /// Installed-app client secrets are not confidential (Google treats them as public).
    var oauthClientID: String?
    var oauthClientSecret: String?
    /// Space-separated scopes to request instead of everything the server advertises.
    var oauthScopes: String?
}

struct IntegrationTool: Identifiable, Equatable, Sendable {
    let pluginID: UUID
    let name: String
    let title: String
    let description: String
    let inputSchema: MCPValue
    let readOnly: Bool
    var id: String { pluginID.uuidString + ":" + name }
}

struct MCPPromptInfo: Identifiable, Sendable {
    struct Argument: Sendable { let name: String; let detail: String?; let required: Bool }
    let pluginID: UUID
    let name: String
    let title: String
    let detail: String?
    let arguments: [Argument]
    var id: String { pluginID.uuidString + ":" + name }
}

struct MCPResourceInfo: Identifiable, Sendable {
    let uri: String
    let name: String
    let detail: String?
    let mimeType: String?
    var id: String { uri }
}

struct IntegrationToolResult: Sendable {
    let text: String
    let isError: Bool
    let content: [MCPValue]
    let structuredContent: MCPValue?
}

struct LocalSkill: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var summary: String
    var instructions: String
    var sourcePath: String
    var enabled = true
    var importedAt = Date()
}

enum MCPError: LocalizedError {
    case invalidConfiguration(String), disconnected, timeout, invalidResponse, server(Int), http(Int), sessionExpired, cancelled, storage
    case unsupportedVersion([String]), capabilityRequired, headerMismatch, declined
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .disconnected: return "This server is disconnected. Connect it in Integrations."
        case .timeout: return "The server did not respond in time. Check the server and try again."
        case .invalidResponse: return "The server returned an invalid MCP response."
        case .server(let code): return "The server rejected this request (MCP error \(code))."
        case .http(let status): return "The server returned HTTP \(status). Check its address and credentials."
        case .sessionExpired: return "The server session expired. Reconnect before retrying this action."
        case .cancelled: return "The request was cancelled."
        case .storage: return "Speek could not save the integration. Check available storage and try again."
        case .unsupportedVersion: return "This server uses an incompatible MCP version. Speek supports 2026-07-28 and initialization-based versions through 2025-11-25."
        case .capabilityRequired: return "This tool requires a client capability Speek has not enabled, such as interactive server input. No follow-up was executed."
        case .headerMismatch: return "The server rejected the tool's request headers. Test the connection to refresh its tool definitions."
        case .declined: return "You declined the plugin's request, so the action stopped."
        }
    }
}

/// Answers a request the server sends back mid-call (for example `elicitation/create`).
/// Returns the JSON-RPC `result`; throwing replies with an error.
typealias MCPServerRequestHandler = @Sendable (_ method: String, _ params: MCPValue) async throws -> MCPValue

protocol MCPTransport: AnyObject, Sendable {
    func setServerRequestHandler(_ handler: MCPServerRequestHandler?) async
    func request(method: String, params: MCPValue) async throws -> MCPValue
    func notify(method: String, params: MCPValue) async throws
    func setProtocolVersion(_ version: String) async
    func setToolSchemas(_ tools: [IntegrationTool]) async throws
    func close() async
}

extension MCPTransport {
    func setToolSchemas(_ tools: [IntegrationTool]) async throws {}
    func setServerRequestHandler(_ handler: MCPServerRequestHandler?) async {}
}

/// The JSON-RPC response to a server-initiated request.
func mcpServerResponse(id: MCPValue, method: String, params: MCPValue, handler: MCPServerRequestHandler?) async -> MCPValue {
    if method == "ping" { return .object(["jsonrpc": .string("2.0"), "id": id, "result": .object([:])]) }
    guard let handler else {
        return .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(-32601), "message": .string("Client capability not supported")])])
    }
    do { return .object(["jsonrpc": .string("2.0"), "id": id, "result": try await handler(method, params)]) }
    catch MCPError.declined {
        // The sampling convention for a request the user rejected.
        return .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(-1), "message": .string("User rejected the request")])])
    }
    catch { return .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(-32601), "message": .string(error.localizedDescription)])]) }
}

func mcpResult(from data: Data, matching id: MCPValue) throws -> MCPValue? {
    let message = try JSONDecoder().decode(MCPValue.self, from: data)
    guard message["jsonrpc"]?.string == "2.0", message["id"] == id else { return nil }
    if let error = message["error"], case .number(let code) = error["code"] {
        guard code.isFinite, code.rounded() == code, (-2_147_483_648...2_147_483_647).contains(code) else { throw MCPError.invalidResponse }
        switch Int(code) {
        case -32022: throw MCPError.unsupportedVersion(error["data"]?["supported"]?.array?.compactMap(\.string) ?? [])
        case -32021: throw MCPError.capabilityRequired
        case -32020: throw MCPError.headerMismatch
        default: throw MCPError.server(Int(code))
        }
    }
    guard let result = message["result"] else { throw MCPError.invalidResponse }
    // Results from earlier servers omit the type and count as complete. `input_required`
    // is handled by `MCPProtocol.call`, which answers the questions and retries.
    if let type = result["resultType"]?.string, type != "complete", type != "input_required" { throw MCPError.invalidResponse }
    return result
}
