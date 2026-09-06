import SwiftUI
import AppKit

struct AdvancedConfigurationPage: View {
    @ObservedObject private var settings = SpeekSettings.shared
    @EnvironmentObject private var menuBarManager: MenuBarManager

    var body: some View {
        SpeekPageScroll {
            applicationSection
            voiceModelSection
            appFolderSection
            textInputSection
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
