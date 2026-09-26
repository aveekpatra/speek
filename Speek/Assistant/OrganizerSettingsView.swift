import SwiftUI
import EventKit
import AppKit

/// Embed in the Integrations screen. Opening this view never requests system access.
struct OrganizerSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var statuses: [OrganizerService: EKAuthorizationStatus] = [:]
    @State private var connecting: OrganizerService?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("On this Mac").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(OrganizerService.allCases) { service in
                    if service != OrganizerService.allCases.first { Divider().padding(.leading, 56) }
                    HStack(spacing: 12) {
                        serviceLabel(service).frame(maxWidth: .infinity, alignment: .leading)
                        connectionControl(service).fixedSize()
                    }.padding(16)
                }
            }.settingsSurface()
            Text("Speek reads connected calendars and lists when you ask. Changes require your approval. Manage system access in Privacy & Security.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Connection error: \(error)")
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func serviceLabel(_ service: OrganizerService) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: service == .calendar ? "calendar" : "list.bullet.rectangle")
                .font(.system(size: 19)).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.title).font(.system(size: 13, weight: .medium))
                Text(service == .calendar ? "Find availability and manage events." : "Find, create, and complete reminders.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func connectionControl(_ service: OrganizerService) -> some View {
        if statuses[service] == .fullAccess {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else if connecting == service {
            ProgressView().controlSize(.small).accessibilityLabel("Connecting \(service.title)")
        } else if statuses[service] == .denied || statuses[service] == .restricted {
            Button("Open settings") {
                let pane = service == .calendar ? "Privacy_Calendars" : "Privacy_Reminders"
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
            }.buttonStyle(SpeekActionButtonStyle())
        } else {
            Button("Connect") {
                connecting = service
                error = nil
                Task { @MainActor in
                    do { try await NativeOrganizerTools.shared.requestAccess(to: service) }
                    catch { self.error = error.localizedDescription }
                    connecting = nil
                    refresh()
                }
            }.buttonStyle(SpeekActionButtonStyle()).disabled(connecting != nil)
        }
    }

    private func refresh() {
        for service in OrganizerService.allCases { statuses[service] = NativeOrganizerTools.shared.authorizationStatus(for: service) }
    }
}
