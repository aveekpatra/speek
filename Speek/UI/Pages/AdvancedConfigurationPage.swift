import SwiftUI
import AppKit

struct AdvancedConfigurationPage: View {
    @ObservedObject private var settings = SpeekSettings.shared
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @ObservedObject private var plugins = AgentPluginManager.shared

    var body: some View {
        SpeekPageScroll {
            applicationSection
            voiceModelSection
            appFolderSection
            textInputSection
            agentPluginsSection
            aiModelsSection
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
    }

    private var applicationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Application")
            SpeekGroup {
                SpeekRow("Show in Dock", help: "Hide the Dock icon to run Speek as a menu bar app only.") {
                    Toggle("", isOn: Binding(
                        get: { !menuBarManager.isMenuBarOnly },
                        set: { menuBarManager.isMenuBarOnly = !$0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Start Recording on Menubar Click", help: "Clicking the menu bar icon starts a recording instead of opening the menu. Right-click still opens the menu.") {
                    Toggle("", isOn: $settings.startRecordingOnMenubarClick).labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Always close", help: "Close the recording window as soon as the text has been pasted, even when the paste failed.") {
                    Toggle("", isOn: $settings.alwaysClose).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var voiceModelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Voice model")
            SpeekGroup {
                SpeekRow("Voice model active duration", help: "How long the voice model stays loaded in memory after a recording. Longer keeps the next recording fast; shorter frees RAM.") {
                    Picker("", selection: $settings.modelActiveDuration) {
                        ForEach(ModelActiveDuration.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private var appFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("App folder location")
            SpeekGroup {
                HStack(spacing: 12) {
                    Text(settings.appFolderPath)
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    SpeekPillButton(title: "Change folder...") { chooseFolder() }
                    SpeekHelpButton(text: "Recordings, transcripts and logs are stored here. Pick a folder inside a synced drive to keep them on all your Macs.")
                }
                .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                .frame(minHeight: SpeekDesign.rowMinHeight)
            }
        }
    }

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Text input")
            SpeekGroup {
                SpeekRow("Clipboard content", help: "Speek pastes through the clipboard. Choose whether your previous clipboard is restored afterwards.") {
                    Picker("", selection: $settings.clipboardContent) {
                        ForEach(ClipboardContentPolicy.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SpeekRow("Clipboard history", help: "Keep every result on the clipboard history so clipboard managers can pick it up.") {
                    Toggle("", isOn: $settings.clipboardHistory).labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Paste result text", help: "Turn off to only copy the result to the clipboard without pasting.") {
                    Toggle("", isOn: $settings.pasteResultText).labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Hold shift to auto-send after paste", help: "Hold Shift while stopping a recording to press Return after the text is pasted.") {
                    HStack(spacing: 14) {
                        Image(systemName: "atom").foregroundStyle(.tertiary).font(.system(size: 13))
                        Toggle("", isOn: $settings.holdShiftToAutoSend).labelsHidden().toggleStyle(.switch)
                    }
                }
                SpeekRow("Simulate keypresses", help: "Type the result character by character instead of pasting. Slower, but works in apps that block paste.") {
                    HStack(spacing: 14) {
                        Image(systemName: "atom").foregroundStyle(.tertiary).font(.system(size: 13))
                        Toggle("", isOn: $settings.simulateKeypresses).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
        }
    }

    private var agentPluginsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Agent Plugins", help: "Let coding agents call you when they need input. Speek pops up, you answer by voice, and the reply is sent back to the agent.")
            SpeekGroup {
                ForEach(AgentPlugin.allCases) { plugin in
                    HStack(spacing: 12) {
                        plugin.icon
                            .frame(width: 26, height: 26)
                        Text(plugin.displayName)
                            .font(.system(size: 15))
                        Spacer()
                        if plugins.isInstalled(plugin) {
                            Menu {
                                Button("Uninstall", role: .destructive) { plugins.uninstall(plugin) }
                            } label: {
                                Text("Installed")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        } else {
                            Button("Install") { plugins.install(plugin) }
                                .buttonStyle(.glass)
                        }
                    }
                    .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                    .frame(minHeight: SpeekDesign.rowMinHeight)
                }
            }
            if let message = plugins.lastMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var aiModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("AI Models")
            SpeekGroup {
                SpeekRow("Show experimental models", help: "Lists preview and quantized model builds in the Models library.") {
                    HStack(spacing: 14) {
                        Image(systemName: "atom").foregroundStyle(.tertiary).font(.system(size: 13))
                        Toggle("", isOn: $settings.showExperimentalModels).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: settings.appFolderPath)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.appFolderPath = url.path
        }
    }
}
