import Foundation

private final class MCPRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Credentials must never follow a redirect to another host.
        completionHandler(nil)
    }
}

actor MCPHTTPTransport: MCPTransport {
    private let endpoint: URL
    private let token: String
    private let session: URLSession
    private var sessionID: String?
    private var version = "2025-06-18"
    private var toolHeaderBindings: [String: [MCPHeaderBinding]] = [:]
    private var closed = false
    private let maximumBytes = 8 * 1024 * 1024

    init(endpoint: URL, token: String = "", session: URLSession? = nil) {
        self.endpoint = endpoint
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: MCPRedirectPolicy(), delegateQueue: nil)
    }

    func setProtocolVersion(_ version: String) {
        self.version = version
        if version == MCPProtocol.current { sessionID = nil }
    }

    func setToolSchemas(_ tools: [IntegrationTool]) throws {
        guard version == MCPProtocol.current else { return }
        var bindings: [String: [MCPHeaderBinding]] = [:]
        for tool in tools { bindings[tool.name] = try MCPHeaderBinding.collect(from: tool.inputSchema) }
        toolHeaderBindings = bindings
    }

    func request(method: String, params: MCPValue) async throws -> MCPValue {
        guard !closed else { throw MCPError.disconnected }
        let id = MCPValue.string(UUID().uuidString)
        do {
            return try await withThrowingTaskGroup(of: MCPValue.self) { group in
                group.addTask { try await self.sendRequest(method: method, params: params, id: id) }
                group.addTask { try await Task.sleep(nanoseconds: method == "server/discover" ? 8_000_000_000 : 90_000_000_000); throw MCPError.timeout }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw MCPError.invalidResponse }
                return result
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                if version != MCPProtocol.current {
                    try? await notify(method: "notifications/cancelled", params: .object(["requestId": id, "reason": .string("Cancelled by user")]))
                }
                throw CancellationError()
            }
            if (error as? URLError)?.code == .timedOut { throw MCPError.timeout }
            throw error
        }
    }

    private func sendRequest(method: String, params: MCPValue, id: MCPValue) async throws -> MCPValue {
        let body: MCPValue = .object(["jsonrpc": .string("2.0"), "id": id, "method": .string(method), "params": MCPProtocol.parameters(params, version: version)])
        let (bytes, response) = try await session.bytes(for: makeRequest(body))
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            if http.statusCode == 404, sessionID != nil { throw MCPError.sessionExpired }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 65_536 { throw MCPError.http(http.statusCode) }
            }
            if (try? JSONDecoder().decode(MCPValue.self, from: data))?["error"] != nil {
                _ = try mcpResult(from: data, matching: id)
            }
            throw MCPError.http(http.statusCode)
        }
        if method == "initialize", let value = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            guard value.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { throw MCPError.invalidResponse }
            sessionID = value
        }
        let isStream = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true
        if isStream {
            var eventData = ""
            var count = 0
            var lineData = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                count += 1
                guard count <= maximumBytes else { throw MCPError.invalidResponse }
                if byte != 0x0A { lineData.append(byte); continue }
                if lineData.last == 0x0D { lineData.removeLast() }
                guard let line = String(data: lineData, encoding: .utf8) else { throw MCPError.invalidResponse }
                lineData.removeAll(keepingCapacity: true)
                if line.isEmpty {
                    if !eventData.isEmpty, let result = try mcpResult(from: Data(eventData.utf8), matching: id) { return result }
                    eventData = ""
                } else if line.hasPrefix("data:") {
                    if !eventData.isEmpty { eventData += "\n" }
                    eventData += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
            }
            if !eventData.isEmpty, let result = try mcpResult(from: Data(eventData.utf8), matching: id) { return result }
        } else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                guard data.count <= maximumBytes else { throw MCPError.invalidResponse }
            }
            if let result = try mcpResult(from: data, matching: id) { return result }
        }
        throw MCPError.invalidResponse
    }

    func notify(method: String, params: MCPValue) async throws {
        guard !closed else { throw MCPError.disconnected }
        let body: MCPValue = .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
        let (_, response) = try await session.data(for: makeRequest(body))
        try accept(response)
    }

    func close() async {
        guard !closed else { return }
        closed = true
        if sessionID != nil, var request = try? makeRequest(nil) {
            request.httpMethod = "DELETE"
            request.timeoutInterval = 5
            _ = try? await session.data(for: request)
        }
        session.invalidateAndCancel()
        sessionID = nil
    }

    private func makeRequest(_ body: MCPValue?) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if version == MCPProtocol.current, let body, let method = body["method"]?.string {
            request.setValue(method, forHTTPHeaderField: "Mcp-Method")
            if let name = body["params"]?["name"]?.string ?? body["params"]?["uri"]?.string {
                request.setValue(MCPProtocol.headerValue(name), forHTTPHeaderField: "Mcp-Name")
                if method == "tools/call", let arguments = body["params"]?["arguments"] {
                    for binding in toolHeaderBindings[name] ?? [] {
                        if let value = try binding.value(in: arguments) { request.setValue(value, forHTTPHeaderField: "Mcp-Param-" + binding.name) }
                    }
                }
            }
        }
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = body.flatMap { try? JSONEncoder().encode($0) }
        return request
    }

    private func accept(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidResponse }
        if http.statusCode == 404, sessionID != nil { throw MCPError.sessionExpired }
        guard (200..<300).contains(http.statusCode) else { throw MCPError.http(http.statusCode) }
    }
}
