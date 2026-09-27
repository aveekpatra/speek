import SwiftUI

/// Integrations > Local tools. Speek does not run coding tasks; it listens to Claude Code and
/// Codex through their hooks and shows a reply panel when a session finishes or needs you.
struct CodingAgentHooksView: View {
    @ObservedObject private var manager = AgentPluginManager.shared
    @ObservedObject private var settings = SpeekSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Coding assistants", info: "When Claude Code or Codex finishes a turn, asks a question, or needs permission, Speek shows a reply panel. Type or dictate your answer and it goes back to that session. Speek never starts coding tasks itself.") {
                ForEach(AgentPlugin.allCases) { plugin in
                    if plugin != AgentPlugin.allCases.first { SettingsRowDivider(leading: 60) }
                    let installed = manager.isInstalled(plugin)
                    SettingsRow(title: plugin.displayName, asset: plugin == .codex ? "provider-codex" : "provider-anthropic",
                                value: manager.busy == plugin ? "Connecting" : (installed || plugin.isPresentOnThisMac ? nil : "Not found on this Mac"),
                                info: installed ? plugin.installedDescription : nil) {
                        Toggle("Connect " + plugin.displayName, isOn: Binding(get: { installed }, set: { on in
                            if on { manager.install(plugin) } else { manager.uninstall(plugin) }
                        })).labelsHidden().toggleStyle(.switch)
                            .disabled(manager.busy != nil || (!installed && !plugin.isPresentOnThisMac))
                    }
                }
                SettingsRowDivider()
                SettingsRow(title: "Send dictated replies automatically", info: "Send the reply as soon as dictation finishes, without pressing Return.") {
                    Toggle("Send dictated replies automatically", isOn: $settings.agentAutoSend).labelsHidden().toggleStyle(.switch)
                }
                SettingsRowDivider()
                SettingsRow(title: "Play a sound") {
                    Toggle("Play a sound", isOn: $settings.agentSound).labelsHidden().toggleStyle(.switch)
                }
            }
            if let message = manager.lastMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
