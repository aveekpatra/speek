import Foundation
import os

/// Installs Speek as a real Codex plugin ("speek@speek") from a local marketplace we write
/// under Application Support, then trusts its hooks. Codex only runs hooks the user has
/// reviewed in `/hooks`; the TUI persists that review as `hooks.state."<key>".trusted_hash`
/// in config.toml through the app-server's `config/batchWrite`, so we make the same write
/// through `codex app-server`. Without that step the hooks silently never fire.
enum CodexPluginInstaller {
    static let marketplaceName = "speek"
    static let pluginName = "speek"
    static var pluginID: String { "\(pluginName)@\(marketplaceName)" }

    static let marketplaceDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Speek/codex-marketplace", isDirectory: true)

    private static let logger = Logger(subsystem: "com.aveekpatra.speek", category: "CodexPluginInstaller")

    static var pluginVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Detection

    static func cliPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".npm-global/bin/codex").path
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        let result = run("/bin/zsh", ["-lc", "command -v codex"], timeout: 10)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !path.isEmpty ? path : nil
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    /// True when "speek@speek" is registered in Codex.
    static var isPluginInstalled: Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return false }
        return text.contains("[plugins.\"\(pluginID)\"]")
    }

    /// True when every Speek plugin hook carries a trusted hash in config.toml.
    static var hooksLookTrusted: Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return false }
        return ["session_start", "user_prompt_submit", "pre_tool_use", "post_tool_use", "permission_request", "stop"].allSatisfy {
            text.contains("[hooks.state.\"\(pluginID):hooks.json:\($0):0:0\"]")
        }
    }

    // MARK: Install / uninstall

    static func install(hookScript: URL) throws {
        guard let cli = cliPath() else { throw Failure(message: "The codex command line tool was not found.") }
        try writeMarketplace(hookScript: hookScript)

        // Fresh copy every time: `remove` drops the cached plugin so a changed hook script
        // or version is picked up.
        _ = run(cli, ["plugin", "remove", pluginID], timeout: 60)
        var result = run(cli, ["plugin", "marketplace", "add", marketplaceDirectory.path], timeout: 60)
        if result.status != 0 && !result.output.localizedCaseInsensitiveContains("already") {
            throw Failure(message: "codex plugin marketplace add failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        result = run(cli, ["plugin", "add", pluginID], timeout: 90)
        if result.status != 0 && !isPluginInstalled {
            throw Failure(message: "codex plugin add failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        try trustHooks(cli: cli)
        logger.notice("Codex plugin installed and hooks trusted (\(pluginVersion, privacy: .public))")
    }

    static func uninstall() {
        guard let cli = cliPath() else { return }
        _ = run(cli, ["plugin", "remove", pluginID], timeout: 60)
        _ = run(cli, ["plugin", "marketplace", "remove", marketplaceName], timeout: 30)
        try? FileManager.default.removeItem(at: marketplaceDirectory)
    }

    // MARK: Marketplace layout

    private static func writeMarketplace(hookScript: URL) throws {
        let fm = FileManager.default
        let root = marketplaceDirectory
        let plugin = root.appendingPathComponent("plugins/\(pluginName)", isDirectory: true)
        try? fm.removeItem(at: root)
        for dir in [root.appendingPathComponent(".agents/plugins"), plugin.appendingPathComponent(".codex-plugin"),
                    plugin.appendingPathComponent("skills/speek"), plugin.appendingPathComponent("scripts")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let marketplace: [String: Any] = [
            "name": marketplaceName,
            "interface": ["displayName": "Speek"],
            "plugins": [[
                "name": pluginName,
                "source": ["source": "local", "path": "./plugins/\(pluginName)"],
                "policy": ["installation": "AVAILABLE", "authentication": "ON_INSTALL"],
                "category": "Productivity"
            ]]
        ]
        try writeJSON(marketplace, to: root.appendingPathComponent(".agents/plugins/marketplace.json"))

        let manifest: [String: Any] = [
            "name": pluginName,
            "version": pluginVersion,
            "description": "Speek voice replies for Codex: answer by voice when Codex finishes or needs permission.",
            "author": ["name": "Speek", "url": "https://github.com/aveekpatra/speek"],
            "homepage": "https://github.com/aveekpatra/speek",
            "repository": "https://github.com/aveekpatra/speek",
            "license": "GPL-3.0",
            "keywords": ["speek", "voice", "codex", "hooks"],
            "skills": "./skills/",
            "hooks": "./hooks.json",
            "interface": [
                "displayName": "Speek",
                "shortDescription": "Voice replies for Codex",
                "longDescription": "Speek connects Codex lifecycle hooks to the Speek macOS app so Codex can ask you by voice when it finishes or needs permission, and continue from your spoken reply.",
                "developerName": "Speek",
                "category": "Productivity",
                "capabilities": ["Interactive", "Hooks"],
                "websiteURL": "https://github.com/aveekpatra/speek",
                "defaultPrompt": ["Turn on Speek", "Turn off Speek", "Check Speek status"]
            ]
        ]
        try writeJSON(manifest, to: plugin.appendingPathComponent(".codex-plugin/plugin.json"))

        // Absolute path on purpose: Codex exports CLAUDE_PLUGIN_ROOT / PLUGIN_ROOT to hooks
        // but no CODEX_PLUGIN_ROOT, and the script under Application Support is the one
        // Speek keeps up to date anyway. The copy inside the plugin is for inspection.
        let command = "\"\(hookScript.path)\" codex"
        func entry(_ timeout: Int, matcher: String? = nil) -> [String: Any] {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
            if let matcher { group["matcher"] = matcher }
            return group
        }
        // All six Codex lifecycle hooks. SessionStart and
        // PostToolUse return immediately in the script; PreToolUse only waits for
        // request_user_input (questions).
        let hooks: [String: Any] = [
            "hooks": [
                "SessionStart": [entry(10)],
                "UserPromptSubmit": [entry(10)],
                "PreToolUse": [entry(3600, matcher: "request_user_input")],
                "PostToolUse": [entry(10)],
                "PermissionRequest": [entry(3600)],
                "Stop": [entry(3600)]
            ]
        ]
        try writeJSON(hooks, to: plugin.appendingPathComponent("hooks.json"))

        try AgentHookInstaller.skillMarkdown.write(to: plugin.appendingPathComponent("skills/speek/SKILL.md"), atomically: true, encoding: .utf8)

        let scriptTarget = plugin.appendingPathComponent("scripts/speek-agent-hook")
        try fm.copyItem(at: hookScript, to: scriptTarget)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptTarget.path)
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: Hook trust (app-server JSON-RPC)

    /// Lists the plugin's hooks through `codex app-server` and records each current hash as
    /// trusted, the same write the `/hooks` review screen makes.
    private static func trustHooks(cli: String) throws {
        let server = AppServer(cli: cli)
        defer { server.stop() }
        try server.start()
        _ = try server.call("initialize", ["clientInfo": ["name": "speek", "version": pluginVersion], "capabilities": [:]])
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let list = try server.call("hooks/list", ["cwd": home])
        guard let result = list["result"] as? [String: Any],
              let data = result["data"] as? [[String: Any]] else {
            throw Failure(message: "codex app-server hooks/list returned no data.")
        }
        var edits: [[String: Any]] = []
        for group in data {
            for hook in (group["hooks"] as? [[String: Any]]) ?? [] {
                guard hook["pluginId"] as? String == pluginID,
                      let key = hook["key"] as? String,
                      let hash = hook["currentHash"] as? String else { continue }
                edits.append(["keyPath": "hooks.state.\"\(key)\".trusted_hash", "value": hash, "mergeStrategy": "replace"])
            }
        }
        guard !edits.isEmpty else { throw Failure(message: "Codex does not list the Speek plugin hooks; is the plugin enabled?") }
        let write = try server.call("config/batchWrite", ["edits": edits])
        if let error = write["error"] {
            throw Failure(message: "Could not trust the hooks: \(error)")
        }
    }

    /// Minimal line-delimited JSON-RPC client over `codex app-server` stdio.
    private final class AppServer {
        private let process = Process()
        private let input = Pipe()
        private let output = Pipe()
        private var buffer = Data()
        private var nextID = 1
        private let cli: String

        init(cli: String) { self.cli = cli }

        func start() throws {
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["app-server"]
            process.environment = augmentedEnvironment()
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        func stop() {
            if process.isRunning { process.terminate() }
        }

        func call(_ method: String, _ params: [String: Any], timeout: TimeInterval = 30) throws -> [String: Any] {
            let id = nextID
            nextID += 1
            let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
            var data = try JSONSerialization.data(withJSONObject: request)
            data.append(0x0A)
            input.fileHandleForWriting.write(data)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let line = nextLine() {
                    guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    if let responseID = json["id"] as? Int, responseID == id { return json }
                    continue
                }
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty {
                    if !process.isRunning { break }
                    Thread.sleep(forTimeInterval: 0.05)
                } else {
                    buffer.append(chunk)
                }
            }
            throw Failure(message: "codex app-server did not answer \(method).")
        }

        private func nextLine() -> Data? {
            guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            return Data(line)
        }
    }

    // MARK: Process helper

    private struct RunResult {
        let status: Int32
        let output: String
    }

    private static func augmentedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
        environment["PATH"] = (extraPaths + [(environment["PATH"] ?? "")]).joined(separator: ":")
        return environment
    }

    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = augmentedEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return RunResult(status: -1, output: error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { process.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return RunResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
