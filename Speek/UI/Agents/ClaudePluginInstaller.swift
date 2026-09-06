import Foundation
import os

/// Installs Speek as a real Claude Code plugin ("speek@speek") so it shows up under
/// Your plugins. The plugin lives in a local marketplace
/// directory we write under Application Support; the `claude` CLI registers it.
/// Falls back to plain settings.json hooks when the CLI is not available.
enum ClaudePluginInstaller {
    static let marketplaceName = "speek"
    static let pluginName = "speek"

    static let marketplaceDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Speek/claude-marketplace", isDirectory: true)

    private static let logger = Logger(subsystem: "com.aveekpatra.speek", category: "ClaudePluginInstaller")

    static var pluginVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // MARK: Detection

    /// Path of the `claude` CLI, resolved through the user's login shell so Homebrew,
    /// npm and ~/.local installs are all found.
    static func cliPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/local/claude").path
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        let result = run("/bin/zsh", ["-lc", "command -v claude"], timeout: 10)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !path.isEmpty ? path : nil
    }

    static var installedPluginsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/installed_plugins.json")
    }

    /// True when "speek@speek" is registered with Claude Code.
    static var isPluginInstalled: Bool {
        guard let data = try? Data(contentsOf: installedPluginsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any] else { return false }
        return plugins["\(pluginName)@\(marketplaceName)"] != nil
    }

    // MARK: Install / uninstall

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Writes the marketplace, registers it, installs the plugin. Throws with the CLI's
    /// output when a step fails.
    static func install(hookScript: URL) throws {
        guard let cli = cliPath() else { throw Failure(message: "The claude command line tool was not found.") }
        try writeMarketplace(hookScript: hookScript)

        var result = run(cli, ["plugin", "marketplace", "add", marketplaceDirectory.path, "--scope", "user"], timeout: 60)
        if result.status != 0 && !result.output.localizedCaseInsensitiveContains("already") {
            throw Failure(message: "claude plugin marketplace add failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        // Pick up a changed hook script or version.
        _ = run(cli, ["plugin", "marketplace", "update", marketplaceName], timeout: 60)

        if isPluginInstalled {
            result = run(cli, ["plugin", "update", "\(pluginName)@\(marketplaceName)"], timeout: 90)
        } else {
            result = run(cli, ["plugin", "install", "\(pluginName)@\(marketplaceName)", "--scope", "user"], timeout: 90)
        }
        if result.status != 0 && !isPluginInstalled {
            throw Failure(message: "claude plugin install failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        _ = run(cli, ["plugin", "enable", "\(pluginName)@\(marketplaceName)"], timeout: 30)
        syncCache()
        logger.notice("Claude Code plugin installed (\(pluginVersion, privacy: .public))")
    }

    /// Claude Code caches a plugin per version and does not re-copy it when the version
    /// stays the same, so a changed hook script would never reach the cache. Overwrite
    /// the cached files for the current version with the marketplace copy.
    private static func syncCache() {
        let fm = FileManager.default
        let source = marketplaceDirectory.appendingPathComponent(pluginName, isDirectory: true)
        let cache = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/cache/\(marketplaceName)/\(pluginName)/\(pluginVersion)", isDirectory: true)
        guard fm.fileExists(atPath: cache.path),
              let items = try? fm.contentsOfDirectory(atPath: source.path) else { return }
        for item in items {
            let from = source.appendingPathComponent(item)
            let to = cache.appendingPathComponent(item)
            try? fm.removeItem(at: to)
            try? fm.copyItem(at: from, to: to)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cache.appendingPathComponent("scripts/speek-agent-hook").path)
    }

    static func uninstall() {
        guard let cli = cliPath() else { return }
        _ = run(cli, ["plugin", "uninstall", "\(pluginName)@\(marketplaceName)"], timeout: 60)
        _ = run(cli, ["plugin", "marketplace", "remove", marketplaceName], timeout: 30)
        try? FileManager.default.removeItem(at: marketplaceDirectory)
    }

    // MARK: Marketplace layout

    private static func writeMarketplace(hookScript: URL) throws {
        let fm = FileManager.default
        let root = marketplaceDirectory
        let plugin = root.appendingPathComponent(pluginName, isDirectory: true)
        try? fm.removeItem(at: root)
        for dir in [root.appendingPathComponent(".claude-plugin"), plugin.appendingPathComponent(".claude-plugin"),
                    plugin.appendingPathComponent("hooks"), plugin.appendingPathComponent("skills/speek"), plugin.appendingPathComponent("scripts")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let marketplace: [String: Any] = [
            "name": marketplaceName,
            "description": "Speek voice replies for coding agents.",
            "owner": ["name": "Speek"],
            "plugins": [[
                "name": pluginName,
                "description": "Answer Claude Code by voice. When Claude finishes, asks a question, or needs permission, Speek pops up and sends your reply straight back.",
                "version": pluginVersion,
                "author": ["name": "Speek"],
                "source": "./\(pluginName)",
                "category": "productivity",
                "homepage": "https://github.com/aveekpatra/speek"
            ]]
        ]
        try writeJSON(marketplace, to: root.appendingPathComponent(".claude-plugin/marketplace.json"))

        let manifest: [String: Any] = [
            "name": pluginName,
            "version": pluginVersion,
            "description": "Speek voice integration: reply to Claude Code by voice, approve permissions and answer questions without touching the terminal.",
            "author": ["name": "Speek"],
            "homepage": "https://github.com/aveekpatra/speek"
        ]
        try writeJSON(manifest, to: plugin.appendingPathComponent(".claude-plugin/plugin.json"))

        let command = "\"${CLAUDE_PLUGIN_ROOT}/scripts/speek-agent-hook\" claude"
        func entry(_ timeout: Int, matcher: String? = nil) -> [String: Any] {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
            if let matcher { group["matcher"] = matcher }
            return group
        }
        let hooks: [String: Any] = [
            "description": "Speek voice replies: waits for your answer and returns it to Claude.",
            "hooks": [
                "Stop": [entry(3600)],
                "Notification": [entry(10)],
                "PermissionRequest": [entry(3600)],
                "PreToolUse": [entry(3600, matcher: "AskUserQuestion")],
                "UserPromptSubmit": [entry(10)]
            ]
        ]
        try writeJSON(hooks, to: plugin.appendingPathComponent("hooks/hooks.json"))

        try AgentHookInstaller.skillMarkdown.write(to: plugin.appendingPathComponent("skills/speek/SKILL.md"), atomically: true, encoding: .utf8)

        let scriptTarget = plugin.appendingPathComponent("scripts/speek-agent-hook")
        try fm.copyItem(at: hookScript, to: scriptTarget)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptTarget.path)
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: Process helper

    private struct RunResult {
        let status: Int32
        let output: String
    }

    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
        environment["PATH"] = (extraPaths + [(environment["PATH"] ?? "")]).joined(separator: ":")
        process.environment = environment
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
