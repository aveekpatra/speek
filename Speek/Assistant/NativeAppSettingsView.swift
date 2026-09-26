import SwiftUI
import AppKit

struct NativeAppSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = Set<NativeAppService>()
    @State private var connecting: NativeAppService?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "App automation", info: "Connecting grants macOS Automation access. Sending, note, and playback changes need your review. Disconnecting turns the tools off in Speek; macOS permissions stay in System Settings.", spacing: 16) {
                ForEach(NativeAppService.allCases) { service in
                    if service != NativeAppService.allCases.first { SettingsRowDivider(leading: 56) }
                    SettingsRow(title: service.title, icon: service.symbol, info: detail(service)) { controls(service) }
                }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    @ViewBuilder private func controls(_ service: NativeAppService) -> some View {
        if !NativeAppTools.shared.isInstalled(service) {
            Text("Not installed").font(.system(size: 11)).foregroundStyle(.secondary)
        } else if connecting == service {
            ProgressView().controlSize(.small).accessibilityLabel("Connecting \(service.title)")
        } else if enabled.contains(service) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary).accessibilityLabel("Connected")
                Button("Disconnect") { NativeAppTools.shared.disconnect(service); refresh() }.buttonStyle(SpeekActionButtonStyle())
            }
        } else {
            Button("Connect") {
                connecting = service; error = nil
                Task {
                    do { try await NativeAppTools.shared.connect(service) }
                    catch { self.error = error.localizedDescription }
                    connecting = nil; refresh()
                }
            }.buttonStyle(SpeekActionButtonStyle()).disabled(connecting != nil)
        }
    }
    private func detail(_ service: NativeAppService) -> String {
        switch service {
        case .mail: return "Read Inbox messages, draft, reply, and send."
        case .notes: return "Find, read, create, and append plain-text notes."
        case .music, .spotify: return "Current track, playback, and volume."
        }
    }
    private func refresh() { enabled = Set(NativeAppService.allCases.filter { NativeAppTools.shared.isEnabled($0) }) }
}
