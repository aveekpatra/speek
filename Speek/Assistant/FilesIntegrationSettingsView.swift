import SwiftUI
import AppKit

/// Embed in Integrations > Native apps. The working folder bounds every file tool.
struct FilesIntegrationSettingsView: View {
    @AppStorage("speek.actions.projectFolder") private var folder = ""

    var body: some View {
        SettingsSection(title: "Files", spacing: 16) {
            SettingsRow(title: "Working folder", icon: "folder.fill", value: folder.isEmpty ? nil : folder,
                        info: "File tools stay inside this folder. Coding tasks start here unless you choose another project.") {
                Button(folder.isEmpty ? "Choose folder" : "Change") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                    if panel.runModal() == .OK { folder = panel.url?.path ?? "" }
                }.buttonStyle(SpeekActionButtonStyle())
            }
        }
    }
}
