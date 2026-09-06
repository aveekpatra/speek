import Foundation

/// Installs the `speek-agent-hook` script and wires it into Claude Code
/// (`~/.claude/settings.json` hooks) or Codex (`~/.codex/config.toml` notify).
enum AgentHookInstaller {
    enum InstallError: LocalizedError {
        case bundledScriptMissing
        case cannotWrite(String)
        case invalidSettings(String)

        var errorDescription: String? {
            switch self {
            case .bundledScriptMissing: return "The hook script is missing from the app bundle."
            case .cannotWrite(let path): return "Could not write \(path)."
            case .invalidSettings(let path): return "\(path) is not valid JSON. Fix it and try again."
            }
        }
    }

    static let hooksDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Speek/hooks", isDirectory: true)
    static let scriptURL = hooksDirectory.appendingPathComponent("speek-agent-hook")
    static let codexPreviousNotifyURL = hooksDirectory.appendingPathComponent("codex-notify-previous")

    static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var codexConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    /// Claude Code events Speek listens to. `PreToolUse` is limited to AskUserQuestion.
    private static let claudeEvents: [(event: String, matcher: String?)] = [
        ("Stop", nil),
        ("Notification", nil),
        ("PermissionRequest", nil),
        ("PreToolUse", "AskUserQuestion"),
        ("UserPromptSubmit", nil)
    ]

    // MARK: - Public

    static func install(_ plugin: AgentPlugin) throws {
        try installScript()
        switch plugin {
        case .claudeCode: try installClaude()
        case .codex: try installCodex()
        }
    }

    static func uninstall(_ plugin: AgentPlugin) throws {
        switch plugin {
        case .claudeCode: try uninstallClaude()
        case .codex: try uninstallCodex()
        }
    }

    static func isInstalled(_ plugin: AgentPlugin) -> Bool {
        switch plugin {
        case .claudeCode:
            guard let data = try? Data(contentsOf: claudeSettingsURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any] else { return false }
            return hooks.values.contains { entry in
                guard let groups = entry as? [[String: Any]] else { return false }
                return groups.contains { group in
                    ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains("speek-agent-hook") == true }
                }
            }
        case .codex:
            guard let text = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return false }
            return text.contains("speek-agent-hook")
        }
    }

    // MARK: - Script

    private static func installScript() throws {
        guard let bundled = Bundle.main.url(forResource: "speek-agent-hook", withExtension: "sh") else {
            throw InstallError.bundledScriptMissing
        }
        do {
            try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
            let data = try Data(contentsOf: bundled)
            try data.write(to: scriptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw InstallError.cannotWrite(scriptURL.path)
        }
    }

    private static var claudeCommand: String { "\"\(scriptURL.path)\" claude" }

    // MARK: - Claude Code

    private static func installClaude() throws {
        var json = try readClaudeSettings()
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for spec in claudeEvents {
            var groups = hooks[spec.event] as? [[String: Any]] ?? []
            let alreadyPresent = groups.contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains("speek-agent-hook") == true }
            }
            if alreadyPresent { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": claudeCommand, "timeout": 10]]]
            if let matcher = spec.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[spec.event] = groups
        }
        json["hooks"] = hooks
        try writeClaudeSettings(json)
    }

    private static func uninstallClaude() throws {
        var json = try readClaudeSettings()
        guard var hooks = json["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var group = group
                let remaining = ((group["hooks"] as? [[String: Any]]) ?? []).filter {
                    ($0["command"] as? String)?.contains("speek-agent-hook") != true
                }
                if remaining.isEmpty { return nil }
                group["hooks"] = remaining
                return group
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }
        try writeClaudeSettings(json)
    }

    private static func readClaudeSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return [:] }
        let data = try Data(contentsOf: claudeSettingsURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.invalidSettings(claudeSettingsURL.path)
        }
        return json
    }

    private static func writeClaudeSettings(_ json: [String: Any]) throws {
        do {
            try FileManager.default.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeSettingsURL, options: .atomic)
        } catch {
            throw InstallError.cannotWrite(claudeSettingsURL.path)
        }
    }

    // MARK: - Codex

    private static func installCodex() throws {
        var lines = (try? String(contentsOf: codexConfigURL, encoding: .utf8))?.components(separatedBy: "\n") ?? []
        let ourLine = "notify = [\"\(scriptURL.path)\", \"codex\"]"
        var inserted = false
        var inTable = false
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inTable = true }
            guard !inTable, trimmed.hasPrefix("notify") else { continue }
            if !trimmed.contains("speek-agent-hook") {
                // Remember the previous command so the hook can keep forwarding to it.
                if let previous = shellCommand(fromTOMLArrayLine: trimmed) {
                    try? previous.write(to: codexPreviousNotifyURL, atomically: true, encoding: .utf8)
                }
            }
            lines[index] = ourLine
            inserted = true
            break
        }
        if !inserted {
            // Top-level keys must precede any [table]; insert at the top.
            lines.insert(ourLine, at: 0)
        }
        do {
            try FileManager.default.createDirectory(at: codexConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: codexConfigURL, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.cannotWrite(codexConfigURL.path)
        }
    }

    private static func uninstallCodex() throws {
        guard var lines = (try? String(contentsOf: codexConfigURL, encoding: .utf8))?.components(separatedBy: "\n") else { return }
        let previous = (try? String(contentsOf: codexPreviousNotifyURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in lines.indices where lines[index].contains("speek-agent-hook") && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("notify") {
            if let previous, !previous.isEmpty, let restored = tomlArrayLine(fromShellCommand: previous) {
                lines[index] = restored
            } else {
                lines.remove(at: index)
            }
            break
        }
        try? FileManager.default.removeItem(at: codexPreviousNotifyURL)
        do {
            try lines.joined(separator: "\n").write(to: codexConfigURL, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.cannotWrite(codexConfigURL.path)
        }
    }

    /// `notify = ["prog", "arg"]` -> `'prog' 'arg'`
    private static func shellCommand(fromTOMLArrayLine line: String) -> String? {
        guard let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]") else { return nil }
        let inner = line[line.index(after: open)..<close]
        let items = inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        return items.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }

    /// `'prog' 'arg'` -> `notify = ["prog", "arg"]`
    private static func tomlArrayLine(fromShellCommand command: String) -> String? {
        let items = command.split(separator: "'").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return nil }
        return "notify = [" + items.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"
    }
}
