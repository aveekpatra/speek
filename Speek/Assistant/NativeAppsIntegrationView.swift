import SwiftUI
import EventKit
import AppKit

/// Integrations > Native apps. A finite set Speek ships, so it is a grouped list with one
/// switch per capability: on means Speek may use it. Opening this view never requests access.
struct NativeAppsIntegrationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("speek.actions.projectFolder") private var folder = ""
    @State private var organizer: [OrganizerService: EKAuthorizationStatus] = [:]
    @State private var organizerEnabled = Set<OrganizerService>()
    @State private var apps = Set<NativeAppService>()
    @State private var messagesHistory = false
    @State private var messagesSending = false
    @State private var busy: String?
    @State private var errors: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "Communication", info: "Sending always waits for your review of the exact recipient and message.") {
                appRow(.mail)
                SettingsRowDivider(leading: 60)
                SettingsRow(title: "Read messages", image: AppIcon.image(for: "com.apple.MobileSMS"), value: errors["messages.history"],
                            info: "Recent conversations, search, and unread messages. Needs Full Disk Access for Speek and a restart after granting it. Search covers plain text only.") {
                    HStack(spacing: 10) {
                        if messagesHistory {
                            Button("Full Disk Access") { openPrivacyPane("Privacy_AllFiles") }.buttonStyle(SpeekActionButtonStyle())
                        }
                        Toggle("Read messages", isOn: Binding(get: { messagesHistory }, set: { on in
                            if on { MessagesTools.shared.enableHistory() } else { MessagesTools.shared.disableHistory() }
                            refresh()
                        })).labelsHidden().toggleStyle(.switch).disabled(!MessagesTools.shared.isInstalled)
                    }
                }
                SettingsRowDivider(leading: 60)
                SettingsRow(title: "Send iMessages", image: AppIcon.image(for: "com.apple.MobileSMS"), value: errors["messages.send"],
                            info: "One recipient at a time, by exact phone number or email. Speek never guesses a recipient from a contact name.") {
                    busySwitch("messages.send", title: "Send iMessages", isOn: messagesSending, enabled: MessagesTools.shared.isInstalled) { on in
                        if on { try await MessagesTools.shared.connectSending() } else { MessagesTools.shared.disableSending() }
                    }
                }
            }
            SettingsSection(title: "Organization", info: "Speek reads these when you ask. Every change waits for your approval.") {
                organizerRow(.calendar, bundleID: "com.apple.iCal")
                SettingsRowDivider(leading: 60)
                organizerRow(.reminders, bundleID: "com.apple.reminders")
                SettingsRowDivider(leading: 60)
                appRow(.notes)
            }
            SettingsSection(title: "Media") {
                appRow(.music)
                SettingsRowDivider(leading: 60)
                appRow(.spotify)
            }
            SettingsSection(title: "Files") {
                SettingsRow(title: "Working folder", image: AppIcon.image(for: "com.apple.finder"), value: folder.isEmpty ? "Not set" : folder,
                            info: "File tools stay inside this folder. Coding tasks start here unless you choose another project.") {
                    Button(folder.isEmpty ? "Choose folder" : "Change") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK { folder = panel.url?.path ?? "" }
                    }.buttonStyle(SpeekActionButtonStyle())
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func appRow(_ service: NativeAppService) -> some View {
        let installed = NativeAppTools.shared.isInstalled(service)
        return SettingsRow(title: service.title, icon: service.symbol, image: AppIcon.image(for: service.bundleID),
                           value: installed ? errors[service.rawValue] : "Not installed", info: detail(service)) {
            busySwitch(service.rawValue, title: service.title, isOn: apps.contains(service), enabled: installed) { on in
                if on { try await NativeAppTools.shared.connect(service) } else { NativeAppTools.shared.disconnect(service) }
            }
        }
    }

    private func organizerRow(_ service: OrganizerService, bundleID: String) -> some View {
        let status = organizer[service]
        let denied = status == .denied || status == .restricted
        return SettingsRow(title: service.title, icon: service == .calendar ? "calendar" : "list.bullet.rectangle", image: AppIcon.image(for: bundleID),
                           value: denied ? "Access is off in System Settings" : errors[service.rawValue],
                           info: service == .calendar ? "Find availability and manage events." : "Find, create, and complete reminders.") {
            if denied {
                Button("Open System Settings") { openPrivacyPane(service == .calendar ? "Privacy_Calendars" : "Privacy_Reminders") }
                    .buttonStyle(SpeekActionButtonStyle())
            } else {
                busySwitch(service.rawValue, title: service.title, isOn: status == .fullAccess && organizerEnabled.contains(service), enabled: true) { on in
                    if on && NativeOrganizerTools.shared.authorizationStatus(for: service) != .fullAccess {
                        try await NativeOrganizerTools.shared.requestAccess(to: service)
                    }
                    NativeOrganizerTools.shared.setEnabled(on, for: service)
                }
            }
        }
    }

    /// A switch that shows progress while macOS asks for access, and keeps its state on failure.
    @ViewBuilder private func busySwitch(_ id: String, title: String, isOn: Bool, enabled: Bool, change: @escaping (Bool) async throws -> Void) -> some View {
        if busy == id {
            ProgressView().controlSize(.small).frame(width: 38).accessibilityLabel("Connecting " + title)
        } else {
            Toggle(title, isOn: Binding(get: { isOn }, set: { on in
                busy = id; errors[id] = nil
                Task { @MainActor in
                    do { try await change(on) } catch { errors[id] = error.localizedDescription }
                    busy = nil; refresh()
                }
            })).labelsHidden().toggleStyle(.switch).disabled(!enabled || busy != nil)
        }
    }

    private func detail(_ service: NativeAppService) -> String {
        switch service {
        case .mail: return "Read Inbox messages, draft, reply, and send. Connecting grants macOS Automation access."
        case .notes: return "Find, read, create, and append plain-text notes."
        case .music, .spotify: return "Current track, playback, and volume."
        }
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    private func refresh() {
        for service in OrganizerService.allCases { organizer[service] = NativeOrganizerTools.shared.authorizationStatus(for: service) }
        organizerEnabled = Set(OrganizerService.allCases.filter { NativeOrganizerTools.shared.isEnabled($0) })
        apps = Set(NativeAppService.allCases.filter { NativeAppTools.shared.isEnabled($0) })
        messagesHistory = MessagesTools.shared.historyEnabled
        messagesSending = MessagesTools.shared.sendingEnabled
    }
}
