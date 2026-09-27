import SwiftUI
import AppKit

/// When Speek may use a tool without asking.
enum ToolPolicy: String, Codable, CaseIterable, Identifiable {
    case ask, allow, never
    var id: String { rawValue }
    var title: String {
        switch self { case .ask: return "Ask"; case .allow: return "Always allow"; case .never: return "Never" }
    }
}

/// One tool as shown in Integrations > Approvals.
struct ToolPolicyEntry: Identifiable {
    let id: String
    let title: String
    let summary: String
    /// Changes data, sends, opens, or controls something. Read-only tools are false.
    let changesData: Bool
}

/// Tools grouped by the integration that provides them.
struct ToolPolicyGroup: Identifiable {
    enum Icon { case app(String), symbol(String), asset(String) }
    let id: String
    let title: String
    let icon: Icon
    let tools: [ToolPolicyEntry]
    var note: String? = nil
}

/// Resolution order: a tool's own choice, then the default for reads or changes.
/// MCP and command-line tools store Never in their existing disabled-tool lists, so the
/// agent never sees them; every other Never is filtered from the runtime catalog here.
@MainActor
final class ToolPolicyStore: ObservableObject {
    static let shared = ToolPolicyStore()
    static let computerUseID = "computer.use"

    @Published private(set) var overrides: [String: ToolPolicy] = [:]
    @Published var readDefault: ToolPolicy { didSet { defaults.set(readDefault.rawValue, forKey: "speek.toolPolicy.reads") } }
    @Published var changeDefault: ToolPolicy { didSet { defaults.set(changeDefault.rawValue, forKey: "speek.toolPolicy.changes") } }
    private let defaults = UserDefaults.standard

    private init() {
        readDefault = ToolPolicy(rawValue: defaults.string(forKey: "speek.toolPolicy.reads") ?? "") ?? .allow
        changeDefault = ToolPolicy(rawValue: defaults.string(forKey: "speek.toolPolicy.changes") ?? "") ?? .ask
        if let data = defaults.data(forKey: "speek.toolPolicies"),
           let saved = try? JSONDecoder().decode([String: ToolPolicy].self, from: data) { overrides = saved }
    }

    func defaultPolicy(changesData: Bool) -> ToolPolicy { changesData ? changeDefault : readDefault }

    func policy(for toolID: String, changesData: Bool) -> ToolPolicy {
        if let disabled = disabledExternally(toolID), disabled { return .never }
        // Giving Speek a task on the computer is the permission; it runs unless the user chose otherwise.
        return overrides[toolID] ?? (toolID == Self.computerUseID ? .allow : defaultPolicy(changesData: changesData))
    }

    func override(for toolID: String) -> ToolPolicy? {
        if disabledExternally(toolID) == true { return .never }
        return overrides[toolID]
    }

    /// `nil` returns the tool to the default for its kind.
    func set(_ policy: ToolPolicy?, for toolID: String) {
        if setExternal(policy == .never, for: toolID) {
            if policy == .never { overrides[toolID] = nil } else { overrides[toolID] = policy }
        } else {
            overrides[toolID] = policy
        }
        save()
    }

    func set(_ policy: ToolPolicy?, forAll tools: [ToolPolicyEntry]) {
        for tool in tools { set(policy, for: tool.id) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(overrides), forKey: "speek.toolPolicies")
    }

    // MARK: MCP and command-line tools keep Never in their own stores

    private func disabledExternally(_ toolID: String) -> Bool? {
        if toolID.hasPrefix("cli:") {
            let parts = toolID.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3, let plugin = LocalPluginStore.shared.plugins.first(where: { $0.id.uuidString == parts[1] }) else { return nil }
            return plugin.disabledTools.contains(parts[2])
        }
        let parts = toolID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let plugin = IntegrationStore.shared.plugins.first(where: { $0.id.uuidString == parts[0] }) else { return nil }
        return plugin.disabledTools.contains(parts[1])
    }

    /// Returns true when the tool belongs to an external store (and was updated there).
    private func setExternal(_ disabled: Bool, for toolID: String) -> Bool {
        if toolID.hasPrefix("cli:") {
            let parts = toolID.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3, let id = UUID(uuidString: parts[1]) else { return false }
            try? LocalPluginStore.shared.setToolEnabled(pluginID: id, name: parts[2], enabled: !disabled)
            objectWillChange.send()
            return true
        }
        guard let tool = IntegrationStore.shared.tools.first(where: { $0.id == toolID }) else { return false }
        try? IntegrationStore.shared.setToolEnabled(tool, enabled: !disabled)
        objectWillChange.send()
        return true
    }

    // MARK: Catalog of every tool Speek can use right now

    var groups: [ToolPolicyGroup] {
        var result: [ToolPolicyGroup] = []
        func title(_ name: String) -> String { name.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? name }

        for service in OrganizerService.allCases where NativeOrganizerTools.shared.authorizationStatus(for: service) == .fullAccess && NativeOrganizerTools.shared.isEnabled(service) {
            let prefix = service == .calendar ? "calendar." : "reminders."
            result.append(ToolPolicyGroup(id: service.rawValue, title: service.title, icon: .app(service == .calendar ? "com.apple.iCal" : "com.apple.reminders"),
                tools: NativeOrganizerTools.catalog.filter { $0.name.hasPrefix(prefix) }.map {
                    ToolPolicyEntry(id: $0.name, title: title($0.name), summary: $0.description, changesData: $0.requiresConfirmation)
                }))
        }
        for service in NativeAppService.allCases {
            let app = NativeAppTools.shared.isEnabled(service) && NativeAppTools.shared.isInstalled(service)
            var tools = app ? NativeAppTools.catalog.filter { $0.service == service }.map {
                ToolPolicyEntry(id: $0.name, title: title($0.name), summary: $0.description, changesData: $0.requiresConfirmation)
            } : []
            // The Spotify account's tools sit with the Spotify app's.
            if service == .spotify {
                tools += SpotifyAccount.shared.availableTools.map { ToolPolicyEntry(id: $0.id, title: title($0.id), summary: $0.summary, changesData: $0.requiresReview) }
            }
            guard !tools.isEmpty else { continue }
            result.append(ToolPolicyGroup(id: service.rawValue, title: service.title, icon: .app(service.bundleID), tools: tools))
        }
        let messages = MessagesTools.shared.availableCatalog
        if !messages.isEmpty {
            result.append(ToolPolicyGroup(id: "messages", title: "Messages", icon: .app("com.apple.MobileSMS"),
                tools: messages.map { ToolPolicyEntry(id: $0.name, title: title($0.name), summary: $0.description, changesData: $0.requiresConfirmation) },
                note: "Messages always go to the exact phone number or email you gave."))
        }
        result.append(ToolPolicyGroup(id: "shell", title: "Shell", icon: .app("com.apple.Terminal"),
            tools: [ToolPolicyEntry(id: ShellTool.id, title: ShellTool.tool.title, summary: "Run commands in your login shell. Commands can change anything your account can, so Ask is the safe default.", changesData: true)]))
        result.append(ToolPolicyGroup(id: "files", title: "Files", icon: .app("com.apple.finder"),
            tools: WorkspaceTools.catalog.map { ToolPolicyEntry(id: $0.id, title: $0.title, summary: $0.summary, changesData: $0.requiresReview) }))
        if CodexConnection.binary != nil {
            result.append(ToolPolicyGroup(id: "computer", title: "Computer use", icon: .symbol("cursorarrow.rays"),
                tools: [ToolPolicyEntry(id: Self.computerUseID, title: "Routine actions in apps and the browser",
                                        summary: "Clicking, typing, and navigating for a task you asked for. Ask covers the whole task after one approval. Sensitive actions always ask.",
                                        changesData: true)]))
        }
        result.append(ToolPolicyGroup(id: "schedules", title: "Schedules", icon: .symbol("calendar.badge.clock"),
            tools: ScheduleTools.catalog.map { ToolPolicyEntry(id: $0.id, title: $0.title, summary: $0.summary, changesData: $0.requiresReview) }))
        result.append(ToolPolicyGroup(id: "media", title: "Media keys", icon: .symbol("playpause"),
            tools: MediaTools.catalog.map { ToolPolicyEntry(id: $0.id, title: $0.title, summary: $0.summary, changesData: $0.requiresReview) }))
        result.append(ToolPolicyGroup(id: "web", title: "Web", icon: .symbol("globe"),
            tools: [ToolPolicyEntry(id: "web.search", title: "Search the web", summary: "Search public web pages.", changesData: false),
                    ToolPolicyEntry(id: "web.read", title: "Read a web page", summary: "Read a public HTTPS page from search results.", changesData: false)]))
        for plugin in IntegrationStore.shared.plugins where plugin.enabled {
            let tools = IntegrationStore.shared.tools.filter { $0.pluginID == plugin.id }
            result.append(ToolPolicyGroup(id: plugin.id.uuidString, title: plugin.name, icon: .symbol(plugin.transport == .http ? "server.rack" : "terminal"),
                tools: tools.map { ToolPolicyEntry(id: $0.id, title: $0.title, summary: $0.description, changesData: !$0.readOnly) },
                note: tools.isEmpty ? "Connect this plugin to see its tools." : "Read-only labels come from the server."))
        }
        for plugin in LocalPluginStore.shared.plugins where plugin.enabled {
            result.append(ToolPolicyGroup(id: plugin.id.uuidString, title: plugin.manifest.name, icon: .symbol("terminal"),
                tools: plugin.manifest.tools.map {
                    ToolPolicyEntry(id: "cli:" + plugin.id.uuidString + ":" + $0.name, title: $0.title ?? $0.name, summary: $0.description, changesData: true)
                }))
        }
        return result
    }
}
