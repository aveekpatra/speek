import SwiftUI
import AppKit

/// Agents: first-class home for the Claude Code / Codex integration. Install the hooks,
/// tune how the reply panel behaves, preview it, and learn how to mute it per project.
struct AgentsPage: View {
    @ObservedObject private var plugins = AgentPluginManager.shared
    @ObservedObject private var settings = SpeekSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SpeekPageScroll {
            hero

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Agents", help: "Installing adds a small hook script to the agent's own settings. Uninstalling removes it again. Restart the agent after changing this.")
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
                SpeekSectionHeader("Reply panel")
                SpeekGroup {
                    SpeekRow("Play a sound", help: "A short chime when an agent finishes, asks a question, or needs permission.") {
                        Toggle("", isOn: $settings.agentSound).labelsHidden().toggleStyle(.switch)
                    }
                    SpeekRow("Send dictation right away", help: "Sends your words the moment transcription finishes, without pressing Return. Leave off if you like to review or add screenshots first.") {
                        Toggle("", isOn: $settings.agentAutoSend).labelsHidden().toggleStyle(.switch)
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

    // MARK: Hero

    private var hero: some View {
        SpeekGroup {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(SpeekPage.agents.tileColor.gradient)
                        Image(systemName: SpeekPage.agents.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Talk to your coding agents")
                            .font(.system(size: 17, weight: .semibold))
                        Text("When Claude Code or Codex finishes, asks a question, or needs permission, Speek pops up. Answer by voice and the agent keeps going.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    step(1, "Agent stops", "Finished, a question, or a permission prompt.")
                    step(2, "Speek pops up", "The reply panel shows the message where the recording pill lives.")
                    step(3, "You answer", "Speak, type, paste a screenshot. Return sends it straight back.")
                }
            }
            .padding(SpeekDesign.rowHorizontalPadding)
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(SpeekPage.agents.tileColor))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SpeekDesign.controlFill(scheme).opacity(0.6)))
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
            if installed {
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
