import Foundation
import Combine
import Darwin

struct LocalPluginManifest: Codable, Sendable {
    struct Tool: Codable, Identifiable, Sendable {
        var name: String
        var title: String?
        var description: String
        var inputSchema: MCPValue
        var arguments: [String]
        var timeoutSeconds: Int?
        var id: String { name }
    }
    struct DictationHook: Codable, Sendable {
        var arguments: [String]
        var timeoutSeconds: Int?
    }
    var schemaVersion: Int
    var name: String
    var description: String
    var executable: String
    var workingDirectory: String?
    var tools: [Tool]
    var dictationHook: DictationHook?
}

struct InstalledLocalPlugin: Codable, Identifiable {
    struct AllowedApp: Codable, Identifiable, Equatable {
        var bundleID: String
        var name: String
        var id: String { bundleID }
    }
    var id = UUID()
    var manifest: LocalPluginManifest
    var enabled = false
    var hookEnabled = false
    var hookApplications: [AllowedApp] = []
    var disabledTools: Set<String> = []
    var importedAt = Date()
}

struct LocalPluginTool: Identifiable {
    let pluginID: UUID
    let name: String
    let title: String
    let description: String
    let inputSchema: MCPValue
    var id: String { "cli:" + pluginID.uuidString + ":" + name }
}

struct LocalHookResult { let text: String; let warnings: [String] }

private enum LocalPluginError: LocalizedError {
    case invalid(String), processFailed, timedOut, outputTooLarge, invalidHook
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .processFailed: return "The local tool exited with an error. Check its installation and arguments."
        case .timedOut: return "The local tool exceeded its time limit and was stopped."
        case .outputTooLarge: return "The local tool returned too much output and was stopped."
        case .invalidHook: return "The hook did not return a JSON object with nonempty text. The original dictation was kept."
        }
    }
}

/// Each invocation owns one process. All mutable state is confined to its serial queue.
private final class LocalProcessInvocation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.aveekpatra.speek.local-tool")
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var collected = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var timer: DispatchWorkItem?
    private var complete = false
    private var cancelled = false
    private var exitStatus: Int32?
    private var outputFinished = false
    private static let outputLimit = 1024 * 1024

    func run(executable: String, arguments: [String], directory: String?, payload: Data, timeout: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    if self.cancelled { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    self.process.executableURL = URL(fileURLWithPath: executable)
                    self.process.arguments = arguments
                    if let directory, !directory.isEmpty { self.process.currentDirectoryURL = URL(fileURLWithPath: directory) }
                    let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL"]
                    var environment = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                    self.process.environment = environment
                    self.process.standardInput = self.input
                    self.process.standardOutput = self.output
                    self.process.standardError = self.errors
                    self.output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        let data = handle.availableData
                        self?.queue.async { [weak self] in
                            guard let self else { return }
                            if data.isEmpty {
                                self.outputFinished = true
                                self.output.fileHandleForReading.readabilityHandler = nil
                                self.finishIfExited()
                            } else { self.append(data) }
                        }
                    }
                    self.errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
                    self.process.terminationHandler = { [weak self] process in
                        self?.queue.async { [weak self] in
                            guard let self, !self.complete else { return }
                            self.exitStatus = process.terminationStatus
                            self.finishIfExited()
                        }
                    }
                    do {
                        try self.process.run()
                        // Writing can block when a child ignores stdin, so it never occupies the state queue.
                        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                            guard let self else { return }
                            do {
                                try self.input.fileHandleForWriting.write(contentsOf: payload)
                                try self.input.fileHandleForWriting.close()
                            } catch { self.queue.async { if !self.complete { self.finish(.failure(LocalPluginError.processFailed)) } } }
                        }
                        let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(LocalPluginError.timedOut)) }
                        self.timer = timer
                        self.queue.asyncAfter(deadline: .now() + .seconds(timeout), execute: timer)
                    } catch { self.finish(.failure(LocalPluginError.processFailed)) }
                }
            }
        } onCancel: { self.queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) } }
    }

    private func append(_ data: Data) {
        guard !complete else { return }
        guard collected.count + data.count <= Self.outputLimit else { finish(.failure(LocalPluginError.outputTooLarge)); return }
        collected.append(data)
    }

    private func finishIfExited() {
        guard outputFinished, let exitStatus else { return }
        finish(exitStatus == 0 ? .success(collected) : .failure(LocalPluginError.processFailed))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !complete else { return }
        complete = true
        timer?.cancel()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let child = process
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
final class LocalPluginStore: ObservableObject {
    static let shared = LocalPluginStore()
    @Published private(set) var plugins: [InstalledLocalPlugin] = []
    @Published private(set) var storageError: String?
    private let file: URL

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speek/Integrations", isDirectory: true)
        file = root.appendingPathComponent("local-plugins.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { plugins = try JSONDecoder().decode([InstalledLocalPlugin].self, from: Data(contentsOf: file)) }
        catch { storageError = "The local plugin library could not be read. The saved file was preserved." }
    }

    static func readManifest(from url: URL) throws -> LocalPluginManifest {
        guard url.isFileURL else { throw LocalPluginError.invalid("Choose a local JSON manifest.") }
        let attrs = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attrs.isRegularFile == true, let size = attrs.fileSize, size <= 256_000 else {
            throw LocalPluginError.invalid("Choose a JSON manifest smaller than 256 KB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 256_000 else { throw LocalPluginError.invalid("The manifest is too large.") }
        let manifest: LocalPluginManifest
        do { manifest = try JSONDecoder().decode(LocalPluginManifest.self, from: data) }
        catch { throw LocalPluginError.invalid("This manifest is invalid. Use the example format and check required fields.") }
        try validate(manifest)
        return manifest
    }

    static func validate(_ manifest: LocalPluginManifest) throws {
        guard manifest.schemaVersion == 1 else { throw LocalPluginError.invalid("This manifest version is not supported. Use schemaVersion 1.") }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalPluginError.invalid("The plugin needs a name.") }
        let executable = URL(fileURLWithPath: manifest.executable)
        guard manifest.executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: manifest.executable),
              (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw LocalPluginError.invalid("The executable must be an installed file at an absolute path.")
        }
        if let directory = manifest.workingDirectory, !directory.isEmpty {
            guard directory.hasPrefix("/"), (try? URL(fileURLWithPath: directory).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                throw LocalPluginError.invalid("The working directory must be an existing absolute folder path.")
            }
        }
        guard manifest.tools.count <= 100, !manifest.tools.isEmpty || manifest.dictationHook != nil else { throw LocalPluginError.invalid("Add at least one tool or a dictation hook, and no more than 100 tools.") }
        var names = Set<String>()
        for tool in manifest.tools {
            guard !tool.name.isEmpty, tool.name.count <= 80, names.insert(tool.name).inserted,
                  tool.inputSchema["type"]?.string == "object", tool.arguments.allSatisfy({ !$0.contains("\0") }),
                  (1...120).contains(tool.timeoutSeconds ?? 30) else {
                throw LocalPluginError.invalid("Tool names must be unique, inputs must use an object schema, and timeouts must be 1 to 120 seconds.")
            }
        }
        if let hook = manifest.dictationHook {
            guard (1...15).contains(hook.timeoutSeconds ?? 5), hook.arguments.allSatisfy({ !$0.contains("\0") || $0.isEmpty }) else {
                throw LocalPluginError.invalid("Dictation hook timeouts must be 1 to 15 seconds.")
            }
        }
    }

    func install(_ manifest: LocalPluginManifest) throws {
        guard storageError == nil else { throw MCPError.storage }
        try Self.validate(manifest)
        let previous = plugins
        // Import never grants execution or dictation access automatically.
        plugins.append(InstalledLocalPlugin(manifest: manifest))
        do { try persist() } catch { plugins = previous; throw error }
    }

    func setEnabled(id: UUID, enabled: Bool) throws {
        try update(id) { $0.enabled = enabled; if !enabled { $0.hookEnabled = false } }
    }
    func setToolEnabled(pluginID: UUID, name: String, enabled: Bool) throws {
        try update(pluginID) { if enabled { $0.disabledTools.remove(name) } else { $0.disabledTools.insert(name) } }
    }
    func setHookEnabled(id: UUID, enabled: Bool) throws {
        try update(id) { plugin in
            guard !enabled || (plugin.enabled && plugin.manifest.dictationHook != nil && !plugin.hookApplications.isEmpty) else {
                throw LocalPluginError.invalid("Enable the plugin and choose at least one app before enabling its dictation hook.")
            }
            plugin.hookEnabled = enabled
        }
    }
    func addHookApplication(pluginID: UUID, bundleID: String, name: String) throws {
        guard !bundleID.isEmpty, !bundleID.contains("*"), bundleID.contains(".") else { throw LocalPluginError.invalid("Choose an installed application with a valid bundle identifier.") }
        try update(pluginID) { plugin in
            if !plugin.hookApplications.contains(where: { $0.bundleID == bundleID }) {
                plugin.hookApplications.append(.init(bundleID: bundleID, name: name))
            }
        }
    }
    func removeHookApplication(pluginID: UUID, bundleID: String) throws {
        try update(pluginID) { plugin in
            plugin.hookApplications.removeAll { $0.bundleID == bundleID }
            if plugin.hookApplications.isEmpty { plugin.hookEnabled = false }
        }
    }
    func remove(id: UUID) throws {
        let previous = plugins
        plugins.removeAll { $0.id == id }
        do { try persist() } catch { plugins = previous; throw error }
    }

    var availableTools: [LocalPluginTool] {
        plugins.filter(\.enabled).flatMap { plugin in
            plugin.manifest.tools.filter { !plugin.disabledTools.contains($0.name) }.map {
                LocalPluginTool(pluginID: plugin.id, name: $0.name, title: $0.title ?? $0.name,
                                description: $0.description, inputSchema: $0.inputSchema)
            }
        }
    }

    func execute(toolID: String, arguments: [String: MCPValue]) async throws -> IntegrationToolResult {
        guard let tool = availableTools.first(where: { $0.id == toolID }), let plugin = plugins.first(where: { $0.id == tool.pluginID }),
              let definition = plugin.manifest.tools.first(where: { $0.name == tool.name }) else { throw MCPError.disconnected }
        try Self.validate(plugin.manifest)
        let argv = try Self.resolveArguments(definition.arguments, input: arguments)
        let payload = try JSONEncoder().encode(MCPValue.object(["tool": .string(tool.name), "arguments": .object(arguments)]))
        guard payload.count <= 256_000 else { throw LocalPluginError.invalid("This tool request is too large.") }
        let result = try await LocalProcessInvocation().run(executable: plugin.manifest.executable, arguments: argv,
                                                          directory: plugin.manifest.workingDirectory, payload: payload,
                                                          timeout: definition.timeoutSeconds ?? 30)
        guard let text = String(data: result, encoding: .utf8) else { throw LocalPluginError.invalid("The tool returned non-text output.") }
        let structured = try? JSONDecoder().decode(MCPValue.self, from: result)
        return IntegrationToolResult(text: text, isError: false, content: [.object(["type": .string("text"), "text": .string(text)])], structuredContent: structured)
    }

    func processDictation(text: String, appBundleID: String?) async -> LocalHookResult {
        guard let appBundleID, !text.isEmpty else { return LocalHookResult(text: text, warnings: []) }
        let hooks = plugins.filter { $0.enabled && $0.hookEnabled && $0.manifest.dictationHook != nil && $0.hookApplications.contains(where: { $0.bundleID == appBundleID }) }
        var current = text
        var warnings: [String] = []
        for plugin in hooks {
            if Task.isCancelled { return LocalHookResult(text: text, warnings: warnings) }
            guard let hook = plugin.manifest.dictationHook else { continue }
            do {
                try Self.validate(plugin.manifest)
                let payload = try JSONEncoder().encode(MCPValue.object(["text": .string(current), "appBundleID": .string(appBundleID)]))
                guard payload.count <= 256_000 else { throw LocalPluginError.invalid("The dictation is too long for this hook.") }
                let result = try await LocalProcessInvocation().run(executable: plugin.manifest.executable, arguments: hook.arguments,
                                                                  directory: plugin.manifest.workingDirectory, payload: payload,
                                                                  timeout: hook.timeoutSeconds ?? 5)
                let value = try JSONDecoder().decode(MCPValue.self, from: result)
                guard let revised = value["text"]?.string, !revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      revised.count <= 100_000 else { throw LocalPluginError.invalidHook }
                current = revised
            } catch {
                warnings.append(plugin.manifest.name + ": " + Self.safeError(error))
            }
        }
        return LocalHookResult(text: current, warnings: warnings)
    }

    private static func resolveArguments(_ template: [String], input: [String: MCPValue]) throws -> [String] {
        try template.map { argument in
            guard argument.hasPrefix("{{"), argument.hasSuffix("}}") else { return argument }
            let key = String(argument.dropFirst(2).dropLast(2))
            guard let value = input[key] else { throw LocalPluginError.invalid("Missing argument: " + key) }
            switch value {
            case .string(let text):
                guard !text.contains("\0") else { throw LocalPluginError.invalid("Arguments cannot contain null characters.") }
                return text
            case .number, .bool: return value.jsonString
            default: throw LocalPluginError.invalid("Argument " + key + " must be text, a number or a boolean.")
            }
        }
    }

    private func update(_ id: UUID, mutate: (inout InstalledLocalPlugin) throws -> Void) throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { throw MCPError.disconnected }
        let previous = plugins[index]
        do { try mutate(&plugins[index]); try persist() } catch { plugins[index] = previous; throw error }
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(plugins).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func safeError(_ error: Error) -> String {
        if let known = error as? LocalPluginError { return known.localizedDescription }
        if error is CancellationError { return "Cancelled." }
        if let known = error as? MCPError { return known.localizedDescription }
        return "The local tool could not complete the request. The original text was kept."
    }
}
