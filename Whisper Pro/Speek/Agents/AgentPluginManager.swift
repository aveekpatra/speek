import Foundation
import SwiftUI
import AppKit

enum AgentPlugin: String, CaseIterable, Identifiable {
    case claudeCode
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    @ViewBuilder
    var icon: some View {
        switch self {
        case .claudeCode:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.85, green: 0.47, blue: 0.34).gradient)
                .overlay(Image(systemName: "asterisk").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
        case .codex:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.25, green: 0.35, blue: 0.95).gradient)
                .overlay(Image(systemName: "circle.hexagongrid.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
        }
    }
}

/// Installs and removes the agent hook integrations. The actual hook wiring lives in
/// `AgentHookInstaller` (phase 5); this object tracks state for the UI.
@MainActor
final class AgentPluginManager: ObservableObject {
    static let shared = AgentPluginManager()

    @Published private(set) var lastMessage: String?
    @ObservedObject private var settings = SpeekSettings.shared

    private init() {}

    func isInstalled(_ plugin: AgentPlugin) -> Bool {
        _ = settings.claudeCodePluginInstalled
        _ = settings.codexPluginInstalled
        return AgentHookInstaller.isInstalled(plugin)
    }

    func install(_ plugin: AgentPlugin) {
        do {
            try AgentHookInstaller.install(plugin)
            setInstalled(plugin, true)
            lastMessage = "\(plugin.displayName) plugin installed. Restart \(plugin.displayName) to activate it."
        } catch {
            lastMessage = "Could not install \(plugin.displayName) plugin: \(error.localizedDescription)"
        }
    }

    func uninstall(_ plugin: AgentPlugin) {
        do {
            try AgentHookInstaller.uninstall(plugin)
            setInstalled(plugin, false)
            lastMessage = "\(plugin.displayName) plugin removed."
        } catch {
            lastMessage = "Could not remove \(plugin.displayName) plugin: \(error.localizedDescription)"
        }
    }

    private func setInstalled(_ plugin: AgentPlugin, _ value: Bool) {
        switch plugin {
        case .claudeCode: settings.claudeCodePluginInstalled = value
        case .codex: settings.codexPluginInstalled = value
        }
        objectWillChange.send()
    }
}
