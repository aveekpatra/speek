import SwiftUI
import AppKit

struct MessagesIntegrationSettingsView: View {
    @State private var historyEnabled = false
    @State private var sendingEnabled = false
    @State private var connecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Messages", spacing: 16) {
                SettingsRow(title: "Read history", icon: "text.bubble",
                            info: "Recent conversations, search, and unread messages. Needs Full Disk Access for Speek and a restart after granting it. Search covers plain text only.") {
                    HStack(spacing: 8) {
                        if historyEnabled {
                            Button("Full Disk Access") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                            }.buttonStyle(SpeekActionButtonStyle())
                        }
                        historyControl
                    }
                }
                SettingsRowDivider(leading: 56)
                SettingsRow(title: "Send iMessages", icon: "paperplane",
                            info: "One recipient at a time, after you review the exact phone number or email and message. Speek never guesses a recipient from a contact name.") {
                    sendingControl
                }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.onAppear(perform: refresh)
    }

    private var historyControl: some View {
        Button(historyEnabled ? "Disable" : "Enable") {
            if historyEnabled { MessagesTools.shared.disableHistory() }
            else { MessagesTools.shared.enableHistory() }
            refresh()
        }.buttonStyle(SpeekActionButtonStyle()).disabled(!MessagesTools.shared.isInstalled)
            .accessibilityLabel(historyEnabled ? "Disable Messages history" : "Enable Messages history")
    }
    @ViewBuilder private var sendingControl: some View {
        if connecting {
            ProgressView().controlSize(.small).accessibilityLabel("Connecting Messages")
        } else {
            Button(sendingEnabled ? "Disconnect" : "Connect") {
                if sendingEnabled { MessagesTools.shared.disableSending(); refresh() }
                else {
                    connecting = true; error = nil
                    Task {
                        do { try await MessagesTools.shared.connectSending() }
                        catch { self.error = error.localizedDescription }
                        connecting = false; refresh()
                    }
                }
            }.buttonStyle(SpeekActionButtonStyle()).disabled(!MessagesTools.shared.isInstalled)
        }
    }
    private func refresh() {
        historyEnabled = MessagesTools.shared.historyEnabled
        sendingEnabled = MessagesTools.shared.sendingEnabled
    }
}
