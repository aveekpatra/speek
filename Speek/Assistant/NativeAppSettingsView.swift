import SwiftUI
import AppKit

struct NativeAppSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = Set<NativeAppService>()
    @State private var connecting: NativeAppService?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App automation").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(NativeAppService.allCases) { service in
                    if service != NativeAppService.allCases.first { Divider().padding(.leading, 56) }
                    HStack(spacing: 12) {
                        label(service).frame(maxWidth: .infinity, alignment: .leading)
                        controls(service).fixedSize()
                    }.padding(16)
                }
            }.settingsSurface()
            Text("Connect each app to grant macOS Automation access. Messages, notes, and playback changes require review. Disconnecting disables these tools in Speek; macOS permissions remain in System Settings.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func label(_ service: NativeAppService) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: service.symbol).font(.system(size: 19)).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.title).font(.system(size: 13, weight: .medium))
                Text(detail(service)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
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
