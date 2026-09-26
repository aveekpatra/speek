import Foundation
import Combine
import Security

private struct IntegrationSecrets: Codable {
    var bearerToken = ""
    var environment: [String: String] = [:]
}

private enum IntegrationKeychain {
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.aveekpatra.speek.integrations",
         kSecAttrAccount as String: id.uuidString]
    }
    static func load(_ id: UUID) throws -> IntegrationSecrets {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return IntegrationSecrets() }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MCPError.invalidConfiguration("Speek could not read this integration's credentials from Keychain.")
        }
        return try JSONDecoder().decode(IntegrationSecrets.self, from: data)
    }
    static func save(_ value: IntegrationSecrets, id: UUID) throws {
        let data = try JSONEncoder().encode(value)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MCPError.storage }
        } else if status != errSecSuccess { throw MCPError.storage }
    }
    static func remove(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

@MainActor
final class IntegrationStore: ObservableObject {
    static let shared = IntegrationStore()

    enum ConnectionState: Equatable {
        case disconnected, connecting, connected(Int), failed(String)
        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting"
            case .connected(let count): return count == 1 ? "1 tool available" : "\(count) tools available"
            case .failed: return "Connection failed"
            }
        }
    }

    @Published private(set) var plugins: [MCPPlugin] = []
    @Published private(set) var skills: [LocalSkill] = []
    @Published private(set) var states: [UUID: ConnectionState] = [:]
    @Published private(set) var tools: [IntegrationTool] = []
    @Published private(set) var storageError: String?
    private var clients: [UUID: any MCPTransport] = [:]
    private var generations: [UUID: UUID] = [:]
    private var hasRestored = false
    private let file: URL
    private struct Saved: Codable { var plugins: [MCPPlugin]; var skills: [LocalSkill] }

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speek/Integrations", isDirectory: true)
        file = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
            plugins = saved.plugins
            skills = saved.skills
        } catch { storageError = "The integration library could not be read. The saved file has been preserved." }
    }

    func state(for id: UUID) -> ConnectionState { states[id] ?? .disconnected }

    func save(_ plugin: MCPPlugin, bearerToken: String? = nil, environment: [String: String]? = nil) throws {
        guard storageError == nil else { throw MCPError.storage }
        guard state(for: plugin.id) != .connecting else { throw MCPError.invalidConfiguration("Cancel the connection attempt before editing this server.") }
        var value = plugin
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw MCPError.invalidConfiguration("Enter a name for this server.") }
        try Self.validate(value)
        if bearerToken != nil || environment != nil {
            var secrets = try IntegrationKeychain.load(plugin.id)
            if let bearerToken { secrets.bearerToken = bearerToken }
            if let environment { secrets.environment = environment }
            try IntegrationKeychain.save(secrets, id: value.id)
        }
        if clients[value.id] != nil { disconnect(pluginID: value.id) }
        let previous = plugins
        if let index = plugins.firstIndex(where: { $0.id == value.id }) { plugins[index] = value }
        else { plugins.append(value) }
        do { try persist() } catch { plugins = previous; throw error }
    }

    static func validate(_ plugin: MCPPlugin) throws {
        if plugin.transport == .http {
            guard let url = URL(string: plugin.endpoint), let host = url.host, url.user == nil, url.password == nil,
                  url.fragment == nil, url.query == nil,
                  url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
                throw MCPError.invalidConfiguration("Use an HTTPS MCP address, or HTTP on localhost. Put credentials in the token field, not the address.")
            }
        } else {
            guard plugin.executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: plugin.executable) else {
                throw MCPError.invalidConfiguration("Choose the absolute path of an installed executable.")
            }
            guard !plugin.arguments.contains(where: { $0.contains("\0") }) else {
                throw MCPError.invalidConfiguration("Arguments cannot contain null characters.")
            }
        }
    }

    func connect(pluginID id: UUID) async throws {
        guard let plugin = plugins.first(where: { $0.id == id }) else { throw MCPError.disconnected }
        guard state(for: id) != .connecting else { return }
        try Self.validate(plugin)
        let generation = UUID()
        generations[id] = generation
        let old = clients.removeValue(forKey: id)
        tools.removeAll { $0.pluginID == id }
        states[id] = .connecting
        await old?.close()
        guard generations[id] == generation else { throw CancellationError() }
        var client: (any MCPTransport)?
        do {
            try Task.checkCancellation()
            let secrets = try IntegrationKeychain.load(id)
            let newClient: any MCPTransport
            if plugin.transport == .http {
                newClient = MCPHTTPTransport(endpoint: URL(string: plugin.endpoint)!, token: secrets.bearerToken)
            } else {
                newClient = try MCPStdioTransport(executable: plugin.executable, arguments: plugin.arguments,
                                                 workingDirectory: plugin.workingDirectory, environment: secrets.environment)
            }
            client = newClient
            clients[id] = newClient
            let initialized = try await MCPProtocol.discover(newClient, usingHTTP: plugin.transport == .http)
            var found: [IntegrationTool] = []
            if initialized["capabilities"]?["tools"] != nil {
                var cursor: String?
                var seenCursors = Set<String>()
                repeat {
                    try Task.checkCancellation()
                    let params: MCPValue = .object(cursor.map { ["cursor": .string($0)] } ?? [:])
                    let result = try await newClient.request(method: "tools/list", params: params)
                    guard let list = result["tools"]?.array else { throw MCPError.invalidResponse }
                    for tool in list {
                        guard let name = tool["name"]?.string, !name.isEmpty, name.count <= 128,
                              let schema = tool["inputSchema"], schema.object != nil else { throw MCPError.invalidResponse }
                        found.append(IntegrationTool(pluginID: id, name: name, title: tool["title"]?.string ?? name,
                                                     description: tool["description"]?.string ?? "", inputSchema: schema,
                                                     readOnly: tool["annotations"]?["readOnlyHint"]?.bool == true))
                    }
                    guard found.count <= 2000 else { throw MCPError.invalidResponse }
                    cursor = result["nextCursor"]?.string
                    if let cursor, !seenCursors.insert(cursor).inserted { throw MCPError.invalidResponse }
                    guard seenCursors.count < 100 else { throw MCPError.invalidResponse }
                } while cursor != nil
            }
            guard generations[id] == generation, plugins.contains(where: { $0.id == id }) else { throw CancellationError() }
            try await newClient.setToolSchemas(found)
            guard generations[id] == generation, plugins.contains(where: { $0.id == id }) else { throw CancellationError() }
            tools += Dictionary(grouping: found, by: \.id).compactMap { $0.value.first }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            states[id] = .connected(found.count)
            if let index = plugins.firstIndex(where: { $0.id == id }) { plugins[index].enabled = true }
            try persist()
        } catch {
            await client?.close()
            if generations[id] == generation {
                clients.removeValue(forKey: id)
                tools.removeAll { $0.pluginID == id }
                states[id] = error is CancellationError ? .disconnected : .failed(Self.safeError(error))
            }
            throw error
        }
    }

    func disconnect(pluginID id: UUID) {
        generations[id] = UUID()
        let client = clients.removeValue(forKey: id)
        tools.removeAll { $0.pluginID == id }
        states[id] = .disconnected
        if let index = plugins.firstIndex(where: { $0.id == id }) { plugins[index].enabled = false }
        do { try persist() } catch { storageError = MCPError.storage.localizedDescription }
        Task { await client?.close() }
    }

    func remove(pluginID id: UUID) throws {
        disconnect(pluginID: id)
        let previous = plugins
        plugins.removeAll { $0.id == id }
        do { try persist() } catch { plugins = previous; throw error }
        IntegrationKeychain.remove(id)
        states.removeValue(forKey: id)
    }

    func setToolEnabled(_ tool: IntegrationTool, enabled: Bool) throws {
        guard let index = plugins.firstIndex(where: { $0.id == tool.pluginID }) else { throw MCPError.disconnected }
        let previous = plugins[index]
        if enabled { plugins[index].disabledTools.remove(tool.name) }
        else { plugins[index].disabledTools.insert(tool.name) }
        do { try persist() } catch { plugins[index] = previous; throw error }
    }

    var availableTools: [IntegrationTool] {
        tools.filter { tool in plugins.contains { $0.id == tool.pluginID && $0.enabled && !$0.disabledTools.contains(tool.name) } }
    }

    func execute(toolID: String, arguments: [String: MCPValue]) async throws -> IntegrationToolResult {
        guard let tool = availableTools.first(where: { $0.id == toolID }), let client = clients[tool.pluginID] else { throw MCPError.disconnected }
        do {
            let result = try await client.request(method: "tools/call", params: .object(["name": .string(tool.name), "arguments": .object(arguments)]))
            let content = result["content"]?.array ?? []
            let text = content.compactMap { item -> String? in
                if item["type"]?.string == "text" { return item["text"]?.string }
                if item["type"]?.string == "resource" { return item["resource"]?["text"]?.string }
                return nil
            }.joined(separator: "\n")
            return IntegrationToolResult(text: text.isEmpty ? (result["structuredContent"]?.jsonString ?? "Tool completed without text output.") : text,
                                         isError: result["isError"]?.bool == true, content: content, structuredContent: result["structuredContent"])
        } catch {
            switch error {
            case MCPError.sessionExpired, MCPError.disconnected:
                disconnect(pluginID: tool.pluginID)
                states[tool.pluginID] = .failed(Self.safeError(error))
            default: break
            }
            throw error
        }
    }

    func restoreEnabledConnections() async {
        guard !hasRestored else { return }
        hasRestored = true
        let ids = plugins.filter(\.enabled).map(\.id)
        for id in ids { try? await connect(pluginID: id) }
    }

    func importSkill(from url: URL) throws {
        guard storageError == nil else { throw MCPError.storage }
        let source = url.hasDirectoryPath ? url.appendingPathComponent("SKILL.md") : url
        guard source.lastPathComponent == "SKILL.md" else { throw MCPError.invalidConfiguration("Choose a SKILL.md file or its containing folder.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 256_000 else {
            throw MCPError.invalidConfiguration("Skill instructions must be smaller than 256 KB.")
        }
        let text = try String(contentsOf: source, encoding: .utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MCPError.invalidConfiguration("This skill has no instructions.") }
        var name = source.deletingLastPathComponent().lastPathComponent
        var summary = "Imported instructions"
        let lines = text.components(separatedBy: .newlines)
        if lines.first == "---" {
            for line in lines.dropFirst().prefix(while: { $0 != "---" }) {
                if line.hasPrefix("name:") { name = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                if line.hasPrefix("description:") { summary = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            }
        }
        let previous = skills
        if let index = skills.firstIndex(where: { $0.sourcePath == source.path }) {
            skills[index].name = name; skills[index].summary = summary; skills[index].instructions = text; skills[index].importedAt = Date()
        } else { skills.append(LocalSkill(name: name, summary: summary, instructions: text, sourcePath: source.path)) }
        do { try persist() } catch { skills = previous; throw error }
    }

    func setSkillEnabled(id: UUID, enabled: Bool) throws {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        let previous = skills[index].enabled
        skills[index].enabled = enabled
        do { try persist() } catch { skills[index].enabled = previous; throw error }
    }

    func removeSkill(id: UUID) throws {
        let previous = skills
        skills.removeAll { $0.id == id }
        do { try persist() } catch { skills = previous; throw error }
    }

    func enabledSkillInstructions(for query: String) -> String {
        let terms = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 2 }.map(String.init))
        let matches = skills.filter(\.enabled).map { skill in
            let text = (skill.name + " " + skill.summary).lowercased()
            return (skill, terms.filter { text.contains($0) }.count)
        }.filter { query.isEmpty || $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(4)
        return matches.map { "Skill: \($0.0.name)\n" + String($0.0.instructions.prefix(8000)) }.joined(separator: "\n\n")
    }

    private func persist() throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Saved(plugins: plugins, skills: skills))
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func safeError(_ error: Error) -> String {
        if let known = error as? MCPError { return known.localizedDescription }
        if error is CancellationError { return "Connection cancelled." }
        return "The server could not complete the request. Check the connection and try again."
    }
}
