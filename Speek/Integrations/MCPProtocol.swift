import Foundation

/// Supports the stateless July 2026 protocol and the initialization-based revisions.
enum MCPProtocol {
    static let current = "2026-07-28"
    static let legacy = "2025-11-25"
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static func parameters(_ value: MCPValue, version: String) -> MCPValue {
        guard version == current else { return value }
        var fields = value.object ?? [:]
        var metadata = fields["_meta"]?.object ?? [:]
        metadata["io.modelcontextprotocol/protocolVersion"] = .string(version)
        metadata["io.modelcontextprotocol/clientInfo"] = .object(["name": .string("Speek"), "version": .string("1.0")])
        metadata["io.modelcontextprotocol/clientCapabilities"] = .object([:])
        fields["_meta"] = .object(metadata)
        return .object(fields)
    }

    static func discover(_ transport: any MCPTransport, usingHTTP: Bool) async throws -> MCPValue {
        await transport.setProtocolVersion(current)
        do {
            let result = try await transport.request(method: "server/discover", params: .object([:]))
            guard let supported = result["supportedVersions"]?.array?.compactMap(\.string) else { throw MCPError.invalidResponse }
            guard supported.contains(current) else { throw MCPError.unsupportedVersion(supported) }
            guard result["capabilities"]?.object != nil else { throw MCPError.invalidResponse }
            return result
        } catch {
            try Task.checkCancellation()
            // Recognized modern errors never cause a downgrade to legacy semantics.
            switch error {
            case MCPError.unsupportedVersion, MCPError.capabilityRequired, MCPError.headerMismatch: throw error
            case MCPError.http(let status) where ![400, 404, 405].contains(status): throw error
            default:
                if usingHTTP, !(error is MCPError) { throw error }
            }
        }
        await transport.setProtocolVersion(legacy)
        // Speek answers server questions (form and link requests) during a tool call.
        let result = try await transport.request(method: "initialize", params: .object([
            "protocolVersion": .string(legacy), "capabilities": .object(["elicitation": .object(["form": .object([:]), "url": .object([:])])]),
            "clientInfo": .object(["name": .string("Speek"), "version": .string("1.0")])
        ]))
        guard let version = result["protocolVersion"]?.string, legacyVersions.contains(version) else {
            throw MCPError.unsupportedVersion(result["protocolVersion"]?.string.map { [$0] } ?? [])
        }
        await transport.setProtocolVersion(version)
        try await transport.notify(method: "notifications/initialized", params: .object([:]))
        return result
    }

    static func headerValue(_ value: String) -> String {
        let plain = value.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
            && value == value.trimmingCharacters(in: .whitespaces)
            && !(value.hasPrefix("=?base64?") && value.hasSuffix("?="))
        return plain ? value : "=?base64?" + Data(value.utf8).base64EncodedString() + "?="
    }
}

struct MCPHeaderBinding: Sendable {
    let name: String
    let path: [String]
    let type: String

    static func collect(from schema: MCPValue) throws -> [MCPHeaderBinding] {
        var bindings: [MCPHeaderBinding] = []
        var seen = Set<String>()
        let tokenCharacters = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        func containsHeader(_ node: MCPValue) -> Bool {
            if let object = node.object { return object["x-mcp-header"] != nil || object.values.contains(where: containsHeader) }
            return node.array?.contains(where: containsHeader) ?? false
        }
        func walk(_ node: MCPValue, path: [String], depth: Int) throws {
            guard depth < 32, bindings.count <= 128 else { throw MCPError.invalidResponse }
            guard let object = node.object else { return }
            if let annotation = object["x-mcp-header"] {
                guard !path.isEmpty, let name = annotation.string, !name.isEmpty,
                      name.unicodeScalars.allSatisfy({ tokenCharacters.contains($0) }),
                      seen.insert(name.lowercased()).inserted,
                      let type = object["type"]?.string, ["string", "integer", "boolean"].contains(type) else { throw MCPError.invalidResponse }
                bindings.append(MCPHeaderBinding(name: name, path: path, type: type))
            }
            for (key, value) in object {
                if key == "properties", let properties = value.object {
                    for (name, child) in properties { try walk(child, path: path + [name], depth: depth + 1) }
                } else if key != "x-mcp-header", containsHeader(value) { throw MCPError.invalidResponse }
            }
        }
        try walk(schema, path: [], depth: 0)
        return bindings
    }

    func value(in arguments: MCPValue) throws -> String? {
        var current: MCPValue? = arguments
        for key in path { current = current?[key] }
        guard let current, current != .null else { return nil }
        let value: String
        switch (type, current) {
        case ("string", .string(let text)): value = text
        case ("boolean", .bool(let bool)): value = bool ? "true" : "false"
        case ("integer", .number(let number)) where number.isFinite && number.rounded() == number && abs(number) <= 9_007_199_254_740_991:
            value = String(Int64(number))
        default: throw MCPError.invalidConfiguration("A tool parameter has an invalid HTTP header value.")
        }
        let encoded = MCPProtocol.headerValue(value)
        guard encoded.utf8.count <= 16_384 else { throw MCPError.invalidConfiguration("A tool parameter is too large for its required HTTP header.") }
        return encoded
    }
}
