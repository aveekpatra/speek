import SwiftUI
import AppKit

/// Agents: first-class home for the Claude Code / Codex integration. Install the hooks,
/// tune how the reply panel behaves, preview it, and learn how to mute it per project.
struct AgentsPage: View {
    @ObservedObject private var plugins = AgentPluginManager.shared
    @ObservedObject private var settings = SpeekSettings.shared

    var body: some View {
        SpeekPageScroll {
            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Agents", help: "Connecting adds a small hook script to the agent's own settings. Uninstalling removes it again. Restart the agent after changing this.")
                SpeekGroup {
                    ForEach(AgentPlugin.allCases) { plugin in
                        agentRow(plugin)
                    }
                }
                if let message = plugins.lastMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Panel", help: "The reply panel is always horizontally centred on the screen. Bottom and Top keep that edge locked while the panel grows; Center stays centred both ways.")
                SpeekGroup {
                    SpeekRow("Position", help: "Bottom, Center, or Top of the screen. The recording pill has its own position under Configuration.") {
                        SpeekSegmentedPicker(selection: $settings.agentPanelPosition, options: AgentPanelPosition.allCases) { $0.displayName }
                    }
                    SpeekRow("Play a sound", help: "A short chime when an agent finishes, asks a question, or needs permission.") {
                        Toggle("", isOn: $settings.agentSound).labelsHidden().toggleStyle(.switch)
                    }
                    SpeekRow("Send dictation right away", help: "Sends your words the moment transcription finishes, without pressing Return. Leave off if you like to review or add screenshots first.") {
                        Toggle("", isOn: $settings.agentAutoSend).labelsHidden().toggleStyle(.switch)
                    }
                    SpeekRow("Hide duration", help: "How long the panel stays away after Hide (Cmd+H). It comes back by itself, on the next agent event, or from the menu bar.") {
                        HStack(spacing: 8) {
                            TextField("", value: $settings.agentHideSeconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                                .onChange(of: settings.agentHideSeconds) { _, value in
                                    if value < 3 { settings.agentHideSeconds = 3 }
                                    if value > 600 { settings.agentHideSeconds = 600 }
                                }
                            Text("seconds")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    SpeekRow("Preview the panel", subtitle: "Shows the reply panel with a sample message so you can see where it appears.") {
                        Button("Preview") { showPreview() }
                            .buttonStyle(.glass)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Mute for a project")
                SpeekGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type **/speek off** in the agent's chat to stop Speek popping up for that project, **/speek on** to bring it back, **/speek status** to check. The skill is installed together with the hook.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                    .padding(.vertical, 14)
                }
            }
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
    }

    // MARK: Agent rows

    private func agentRow(_ plugin: AgentPlugin) -> some View {
        let installed = plugins.isInstalled(plugin)
        let present = plugin.isPresentOnThisMac
        return HStack(spacing: 12) {
            plugin.icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.displayName)
                    .font(.system(size: 15))
                Text(installed ? plugin.installedDescription : (present ? "Not connected" : "Not found on this Mac yet. Install works anyway; hooks activate once \(plugin.displayName) runs."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if plugins.busy == plugin {
                ProgressView().controlSize(.small)
            } else if installed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Menu {
                        Button("Reinstall hooks") { plugins.install(plugin) }
                        Button("Uninstall", role: .destructive) { plugins.uninstall(plugin) }
                    } label: {
                        Text("Connected")
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            } else {
                Button("Connect") { plugins.install(plugin) }
                    .buttonStyle(.glassProminent)
                    .tint(Color.accentColor)
            }
        }
        .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
        .frame(minHeight: 60)
    }

    // MARK: Preview

    private func showPreview() {
        var components = URLComponents()
        components.scheme = "speek"
        components.host = "agent-update"
        components.queryItems = [
            .init(name: "agent", value: "claude"),
            .init(name: "event", value: "Stop"),
            .init(name: "cwd", value: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/my-app").path),
            .init(name: "session", value: "preview"),
            .init(name: "message", value: "**Done.** I added the login form and wired it to the API.\n\n- `LoginView.swift` with email and password fields\n- Errors show inline under each field\n\nWant me to add a *Forgot password* link as well?")
        ]
        if let url = components.url, let update = AgentUpdate(url: url) {
            AgentUpdateCenter.shared.receive(update)
        }
    }
}
