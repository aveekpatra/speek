import Foundation

enum ActionCloudProvider: String, CaseIterable, Identifiable {
    case openRouter
    case openAI

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI API"
        }
    }
}

enum ActionCredentials {
    static var voiceProvider: ActionCloudProvider {
        ActionCloudProvider(rawValue: UserDefaults.standard.string(forKey: "speek.actions.voiceProvider") ?? "openRouter") ?? .openRouter
    }

    static var selectedProvider: ActionCloudProvider {
        ActionCloudProvider(rawValue: UserDefaults.standard.string(forKey: "speek.actions.cloudProvider") ?? "openAI") ?? .openAI
    }

    static var activeProvider: ActionCloudProvider? {
        if hasKey(for: selectedProvider) { return selectedProvider }
        let alternate: ActionCloudProvider = selectedProvider == .openAI ? .openRouter : .openAI
        return hasKey(for: alternate) ? alternate : nil
    }

    static func key(for provider: ActionCloudProvider) -> String? {
        let name = provider == .openRouter ? "openrouter" : "openai"
        if let key = APIKeyManager.shared.getAPIKey(forProvider: name), !key.isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let environmentName = provider == .openRouter ? "OPENROUTER_API_KEY" : "OPENAI_API_KEY"
        if let key = ProcessInfo.processInfo.environment[environmentName], !key.isEmpty { return key }
        return localKey(named: environmentName)
    }

    static func hasKey(for provider: ActionCloudProvider) -> Bool {
        key(for: provider).map { !$0.isEmpty } ?? false
    }

    private static func localKey(named name: String) -> String? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek", isDirectory: true)
        let file = directory.appendingPathComponent(".env.local")
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}


enum ActionConnection: String, Codable, CaseIterable, Identifiable {
    case localCodex, openRouter, subscription
    var id: String { rawValue }
    var title: String {
        switch self {
        case .localCodex: return "Codex on this Mac"
        case .openRouter: return "OpenRouter"
        case .subscription: return "ChatGPT subscription"
        }
    }
    var logoAsset: String {
        switch self {
        case .localCodex: return "provider-codex"
        case .subscription: return "provider-openai"
        case .openRouter: return "provider-openrouter"
        }
    }
    var detail: String {
        switch self {
        case .localCodex: return "Uses your existing Codex login. Tools run on this Mac."
        case .openRouter: return "Use your API key and choose a cloud model."
        case .subscription: return "Sign in with ChatGPT through Codex. No API key."
        }
    }
    static var preferred: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "speek.actions.connection") ?? "localCodex") ?? .localCodex
    }
}


// New chats snapshot these values; existing chats keep their own selection.
enum AgentDefaults {
    static func model(for connection: ActionConnection, defaults: UserDefaults = .standard) -> String {
        if connection == .openRouter {
            return defaults.string(forKey: "speek.actions.openRouterRoutingModel") ?? "openai/gpt-6-luna"
        }
        return defaults.string(forKey: "speek.defaults.\(connection.rawValue).model") ?? "gpt-6-luna"
    }
    static func reasoning(for connection: ActionConnection, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: "speek.defaults.\(connection.rawValue).reasoning")
    }
    static func setModel(_ model: String, for connection: ActionConnection, defaults: UserDefaults = .standard) {
        let key = connection == .openRouter ? "speek.actions.openRouterRoutingModel" : "speek.defaults.\(connection.rawValue).model"
        guard self.model(for: connection, defaults: defaults) != model else { return }
        defaults.set(model, forKey: key)
        setReasoning(nil, for: connection, defaults: defaults)
    }
    static func setReasoning(_ effort: String?, for connection: ActionConnection, defaults: UserDefaults = .standard) {
        defaults.set(effort, forKey: "speek.defaults.\(connection.rawValue).reasoning")
    }
}
