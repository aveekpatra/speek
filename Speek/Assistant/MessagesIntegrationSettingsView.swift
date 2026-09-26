import SwiftUI
import AppKit

struct MessagesIntegrationSettingsView: View {
    @State private var historyEnabled = false
    @State private var sendingEnabled = false
    @State private var connecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Messages").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    historyLabel.frame(maxWidth: .infinity, alignment: .leading)
                    historyControl.fixedSize()
                }.padding(16)
                Divider().padding(.leading, 56)
                HStack(spacing: 12) {
                    sendingLabel.frame(maxWidth: .infinity, alignment: .leading)
                    sendingControl.fixedSize()
                }.padding(16)
            }.settingsSurface()
            VStack(alignment: .leading, spacing: 10) {
                Text("Reading history requires Full Disk Access for Speek and a restart after granting it. Enabling history here does not grant that macOS permission. Rich text and attachment-only messages may not be readable; search covers plain text only.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Open Full Disk Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(SpeekActionButtonStyle())
                }
                Text("Sending uses Automation permission and requires review of the exact phone number or email and message. Speek never guesses a recipient from a contact name.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            }
        }.onAppear(perform: refresh)
    }

    private var historyLabel: some View {
        label("Read history", detail: "Recent conversations, search, and unread messages.", symbol: "text.bubble")
    }
    private var sendingLabel: some View {
        label("Send iMessages", detail: "One recipient at a time, after your review.", symbol: "paperplane")
    }
    private func label(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 19)).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
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
