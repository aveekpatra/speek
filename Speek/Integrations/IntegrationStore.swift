import Foundation
import Combine
import Security

private struct IntegrationSecrets: Codable {
    var bearerToken = ""
    var environment: [String: String] = [:]
    var oauth: MCPOAuthSession?

    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        oauth = try container.decodeIfPresent(MCPOAuthSession.self, forKey: .oauth)
    }
}

/// Plugin secrets (tokens, OAuth sessions, environment values).
/// Local builds are re-signed with a self-signed certificate on every install; macOS ties
/// Keychain access to each build for apps without a Team ID, so every relaunch would ask
/// again for every item. Like `KeychainService`, local builds keep secrets in an owner-only
/// file instead; distribution builds use Keychain.
private enum IntegrationKeychain {
    #if LOCAL_BUILD
    private static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Speek/Integrations/secrets.json")
    private static let lock = NSLock()
    private static var cache: [String: IntegrationSecrets]?

    private static func all() -> [String: IntegrationSecrets] {
        if let cache { return cache }
        let loaded = (try? JSONDecoder().decode([String: IntegrationSecrets].self, from: Data(contentsOf: file))) ?? [:]
        cache = loaded
        return loaded
    }

    private static func write(_ value: [String: IntegrationSecrets]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        cache = value
    }

    static func load(_ id: UUID) throws -> IntegrationSecrets {
        lock.lock(); defer { lock.unlock() }
        return all()[id.uuidString] ?? IntegrationSecrets()
    }
    static func save(_ value: IntegrationSecrets, id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        var items = all(); items[id.uuidString] = value
        do { try write(items) } catch { throw MCPError.storage }
    }
    static func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var items = all(); items[id.uuidString] = nil
        try? write(items)
    }
    #else
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
    #endif
}

@MainActor
final class IntegrationStore: ObservableObject {
    static let shared = IntegrationStore()

    enum ConnectionState: Equatable {
        case disconnected, connecting, signingIn, connected(Int), failed(String)
        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting"
            case .signingIn: return "Finish signing in in your browser"
            case .connected(let count): return count == 1 ? "1 tool available" : "\(count) tools available"
            case .failed(let message): return message.hasPrefix("Sign-in required") ? "Sign-in required" : "Connection failed"
            }
        }
    }

    @Published private(set) var plugins: [MCPPlugin] = []
    @Published private(set) var skills: [LocalSkill] = []
    @Published private(set) var states: [UUID: ConnectionState] = [:]
    @Published private(set) var tools: [IntegrationTool] = []
    @Published private(set) var prompts: [UUID: [MCPPromptInfo]] = [:]
    /// Plugins whose server offers resources; exposed to the agent as list/read tools.
    private var resourcePlugins = Set<UUID>()
    static let listResourcesTool = "speek_list_resources"
    static let readResourceTool = "speek_read_resource"
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

    /// Connects, signing in with OAuth when a remote server asks for it and no token was given.
    /// `interactive` false never opens the browser (used when restoring at launch).
    func connect(pluginID id: UUID, interactive: Bool = true) async throws {
        // A server with a pre-registered client may only check auth on tool calls, so sign in first.
        if let plugin = plugins.first(where: { $0.id == id }), plugin.transport == .http, plugin.oauthClientID?.isEmpty == false,
           (try? IntegrationKeychain.load(id))?.oauth == nil {
            guard interactive else { states[id] = .failed("Sign-in required. Click Connect to sign in."); throw MCPError.http(401) }
            try await signIn(plugin)
        }
        do {
            try await connectOnce(pluginID: id)
        } catch MCPError.http(401) {
            guard let plugin = plugins.first(where: { $0.id == id }), plugin.transport == .http,
                  let endpoint = URL(string: plugin.endpoint) else { throw MCPError.http(401) }
            let secrets = try IntegrationKeychain.load(id)
            guard secrets.bearerToken.isEmpty, plugin.tokenCommand == nil, endpoint.host != nil else { throw MCPError.http(401) }
            guard interactive else { states[id] = .failed("Sign-in required. Click Connect to sign in."); throw MCPError.http(401) }
            try await signIn(plugin)
            try await connectOnce(pluginID: id)
        }
    }

    private func signIn(_ plugin: MCPPlugin) async throws {
        guard let endpoint = URL(string: plugin.endpoint) else { throw MCPError.invalidConfiguration("This server address is not valid.") }
        var secrets = try IntegrationKeychain.load(plugin.id)
        states[plugin.id] = .signingIn
        do {
            let client = plugin.oauthClientID.flatMap { $0.isEmpty ? nil : (id: $0, secret: plugin.oauthClientSecret) }
            secrets.oauth = try await MCPOAuth.signIn(endpoint: endpoint, previous: secrets.oauth, client: client, scopes: plugin.oauthScopes)
            try IntegrationKeychain.save(secrets, id: plugin.id)
        } catch {
            states[plugin.id] = .failed(Self.safeError(error)); throw error
        }
    }

    /// Runs a token command in the login shell (so PATH matches Terminal), 10-second limit.
    private static func runTokenCommand(_ command: String) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            if process.isRunning { process.terminate() }
            let token = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0, !token.isEmpty, !token.contains("\n") else {
                throw MCPError.invalidConfiguration("The sign-in command did not return a token. Check that \"" + command + "\" works in Terminal.")
            }
            return token
        }.value
    }

    func hasSignIn(_ id: UUID) -> Bool { (try? IntegrationKeychain.load(id))?.oauth != nil }

    func signOut(pluginID id: UUID) {
        disconnect(pluginID: id)
        guard var secrets = try? IntegrationKeychain.load(id) else { return }
        secrets.oauth = nil
        try? IntegrationKeychain.save(secrets, id: id)
        objectWillChange.send()
    }

    /// A saved access token, refreshed first when it is about to expire.
    private func accessToken(for plugin: MCPPlugin, secrets: inout IntegrationSecrets) async throws -> String {
        let id = plugin.id
        if let command = plugin.tokenCommand, !command.isEmpty { return try await Self.runTokenCommand(command) }
        guard secrets.bearerToken.isEmpty, var session = secrets.oauth else { return secrets.bearerToken }
        if session.needsRefresh {
            session = try await MCPOAuth.refresh(session)
            secrets.oauth = session
            try IntegrationKeychain.save(secrets, id: id)
        }
        return session.accessToken
    }

    private func connectOnce(pluginID id: UUID) async throws {
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
            var secrets = try IntegrationKeychain.load(id)
            let newClient: any MCPTransport
            if plugin.transport == .http {
                let token = try await accessToken(for: plugin, secrets: &secrets)
                // Google's Gmail MCP endpoint needs Developer Preview enrollment; the REST API does not.
                // The endpoint is still used for sign-in discovery.
                newClient = plugin.directoryID == "gmail" ? GmailAPITransport(token: token)
                    : MCPHTTPTransport(endpoint: URL(string: plugin.endpoint)!, token: token)
            } else {
                newClient = try MCPStdioTransport(executable: plugin.executable, arguments: plugin.arguments,
                                                 workingDirectory: plugin.workingDirectory, environment: secrets.environment)
            }
            client = newClient
            clients[id] = newClient
            await newClient.setServerRequestHandler(MCPElicitationCenter.handler(plugin: plugin.name))
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
            // Resources become two read-only tools; prompts are offered in the plugin's detail sheet.
            if initialized["capabilities"]?["resources"] != nil {
                resourcePlugins.insert(id)
                found.append(IntegrationTool(pluginID: id, name: Self.listResourcesTool, title: "List " + plugin.name + " resources",
                                             description: "List documents and data that " + plugin.name + " offers as resources, with their URIs.",
                                             inputSchema: .object(["type": .string("object"), "properties": .object(["cursor": .object(["type": .string("string")])])]), readOnly: true))
                found.append(IntegrationTool(pluginID: id, name: Self.readResourceTool, title: "Read a " + plugin.name + " resource",
                                             description: "Read one resource from " + plugin.name + " by its exact URI from the resource list.",
                                             inputSchema: .object(["type": .string("object"), "properties": .object(["uri": .object(["type": .string("string")])]), "required": .array([.string("uri")])]), readOnly: true))
            } else { resourcePlugins.remove(id) }
            if initialized["capabilities"]?["prompts"] != nil, let list = try? await newClient.request(method: "prompts/list", params: .object([:])) {
                prompts[id] = (list["prompts"]?.array ?? []).prefix(200).compactMap { item in
                    guard let name = item["name"]?.string else { return nil }
                    let arguments = (item["arguments"]?.array ?? []).compactMap { argument -> MCPPromptInfo.Argument? in
                        guard let argumentName = argument["name"]?.string else { return nil }
                        return .init(name: argumentName, detail: argument["description"]?.string, required: argument["required"]?.bool == true)
                    }
                    return MCPPromptInfo(pluginID: id, name: name, title: item["title"]?.string ?? name, detail: item["description"]?.string, arguments: arguments)
                }
            } else { prompts[id] = nil }
            guard generations[id] == generation, plugins.contains(where: { $0.id == id }) else { throw CancellationError() }
            try await newClient.setToolSchemas(found.filter { $0.name != Self.listResourcesTool && $0.name != Self.readResourceTool })
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
        prompts[id] = nil; resourcePlugins.remove(id)
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

    func execute(toolID: String, arguments: [String: MCPValue], retryAfterRefresh: Bool = true) async throws -> IntegrationToolResult {
        guard let tool = availableTools.first(where: { $0.id == toolID }), let client = clients[tool.pluginID] else { throw MCPError.disconnected }
        if tool.name == Self.listResourcesTool {
            let resources = try await listResources(pluginID: tool.pluginID, cursor: arguments["cursor"]?.string)
            let lines = resources.map { "- " + $0.name + " <" + $0.uri + ">" + ($0.detail.map { ": " + $0 } ?? "") }
            return IntegrationToolResult(text: lines.isEmpty ? "No resources." : lines.joined(separator: "\n"), isError: false, content: [], structuredContent: nil)
        }
        if tool.name == Self.readResourceTool {
            guard let uri = arguments["uri"]?.string else { throw MCPError.invalidConfiguration("Provide a resource URI.") }
            return IntegrationToolResult(text: try await readResource(pluginID: tool.pluginID, uri: uri), isError: false, content: [], structuredContent: nil)
        }
        do {
            let result = try await MCPProtocol.call(client, method: "tools/call", params: .object(["name": .string(tool.name), "arguments": .object(arguments)]),
                                                    handler: questionHandler(tool.pluginID))
            let content = result["content"]?.array ?? []
            let text = content.compactMap { item -> String? in
                if item["type"]?.string == "text" { return item["text"]?.string }
                if item["type"]?.string == "resource" { return item["resource"]?["text"]?.string }
                return nil
            }.joined(separator: "\n")
            return IntegrationToolResult(text: text.isEmpty ? (result["structuredContent"]?.jsonString ?? "Tool completed without text output.") : text,
                                         isError: result["isError"]?.bool == true, content: content, structuredContent: result["structuredContent"])
        } catch MCPError.http(401) where retryAfterRefresh {
            // The access token expired mid-session: refresh, reconnect, and retry once.
            try await connect(pluginID: tool.pluginID, interactive: false)
            return try await execute(toolID: toolID, arguments: arguments, retryAfterRefresh: false)
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

    /// Shows a plugin's mid-request questions (forms, links, model requests) in the notch.
    private func questionHandler(_ pluginID: UUID) -> MCPServerRequestHandler {
        MCPElicitationCenter.handler(plugin: plugins.first { $0.id == pluginID }?.name ?? "A plugin")
    }

    func listResources(pluginID: UUID, cursor: String? = nil) async throws -> [MCPResourceInfo] {
        guard let client = clients[pluginID] else { throw MCPError.disconnected }
        let result = try await client.request(method: "resources/list", params: .object(cursor.map { ["cursor": .string($0)] } ?? [:]))
        return (result["resources"]?.array ?? []).prefix(500).compactMap { item in
            guard let uri = item["uri"]?.string else { return nil }
            return MCPResourceInfo(uri: uri, name: item["title"]?.string ?? item["name"]?.string ?? uri, detail: item["description"]?.string, mimeType: item["mimeType"]?.string)
        }
    }

    /// Text of a resource, bounded; binary contents are described, not returned.
    func readResource(pluginID: UUID, uri: String) async throws -> String {
        guard let client = clients[pluginID] else { throw MCPError.disconnected }
        let result = try await MCPProtocol.call(client, method: "resources/read", params: .object(["uri": .string(uri)]), handler: questionHandler(pluginID))
        let parts = (result["contents"]?.array ?? []).map { item -> String in
            if let text = item["text"]?.string { return String(text.prefix(60_000)) }
            return "[Binary content: " + (item["mimeType"]?.string ?? "unknown type") + "]"
        }
        return parts.isEmpty ? "The resource is empty." : parts.joined(separator: "\n\n")
    }

    /// The prompt's messages as one text, ready to use as a request.
    func prompt(_ info: MCPPromptInfo, arguments: [String: String]) async throws -> String {
        guard let client = clients[info.pluginID] else { throw MCPError.disconnected }
        let result = try await MCPProtocol.call(client, method: "prompts/get", params: .object([
            "name": .string(info.name), "arguments": .object(arguments.mapValues { .string($0) })
        ]), handler: questionHandler(info.pluginID))
        let texts = (result["messages"]?.array ?? []).compactMap { message -> String? in
            if let text = message["content"]?["text"]?.string { return text }
            if let resource = message["content"]?["resource"]?["text"]?.string { return resource }
            return nil
        }
        guard !texts.isEmpty else { throw MCPError.invalidResponse }
        return texts.joined(separator: "\n\n")
    }

    func restoreEnabledConnections() async {
        guard !hasRestored else { return }
        hasRestored = true
        let ids = plugins.filter(\.enabled).map(\.id)
        for id in ids { try? await connect(pluginID: id, interactive: false) }
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
        if let auth = error as? MCPOAuthError { return auth.localizedDescription }
        if case MCPError.http(401) = error { return "Sign-in required, or the saved token was rejected. Click Connect to sign in, or update the token in Edit." }
        if let known = error as? MCPError { return known.localizedDescription }
        if error is CancellationError { return "Connection cancelled." }
        return "The server could not complete the request. Check the connection and try again."
    }
}

/// OAuth sessions for built-in services (Spotify), stored the same way as plugin secrets.
enum ServiceTokenStore {
    static func load(_ id: UUID) -> MCPOAuthSession? { (try? IntegrationKeychain.load(id))?.oauth }
    static func save(_ session: MCPOAuthSession, id: UUID) throws {
        var secrets = IntegrationSecrets()
        secrets.oauth = session
        try IntegrationKeychain.save(secrets, id: id)
    }
    static func remove(_ id: UUID) { IntegrationKeychain.remove(id) }
}
