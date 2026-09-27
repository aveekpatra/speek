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
    @State private var expanded: Set<String> = []
    @ObservedObject private var policies = ToolPolicyStore.shared

    private func isOpen(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) }, set: { open in if open { expanded.insert(key) } else { expanded.remove(key) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "Communication", info: "Sending always waits for your review of the exact recipient and message.") {
                appRow(.mail)
                SettingsRowDivider(leading: 60)
                let readTools = messagesHistory ? policies.tools(inGroup: "messages").filter { !$0.changesData } : []
                SettingsRow(title: "Read messages", image: AppIcon.image(for: "com.apple.MobileSMS"), value: errors["messages.history"] ?? policies.summary(readTools),
                            info: "Recent conversations, search, and unread messages. Needs Full Disk Access for Speek and a restart after granting it. Search covers plain text only.",
                            expanded: readTools.isEmpty ? nil : isOpen("messages.read")) {
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
                if expanded.contains("messages.read") && !readTools.isEmpty { ToolPolicyRows(tools: readTools) }
                SettingsRowDivider(leading: 60)
                let sendTools = messagesSending ? policies.tools(inGroup: "messages").filter(\.changesData) : []
                SettingsRow(title: "Send iMessages", image: AppIcon.image(for: "com.apple.MobileSMS"), value: errors["messages.send"] ?? policies.summary(sendTools),
                            info: "One recipient at a time, by exact phone number or email. Speek never guesses a recipient from a contact name.",
                            expanded: sendTools.isEmpty ? nil : isOpen("messages.send")) {
                    busySwitch("messages.send", title: "Send iMessages", isOn: messagesSending, enabled: MessagesTools.shared.isInstalled) { on in
                        if on { try await MessagesTools.shared.connectSending() } else { MessagesTools.shared.disableSending() }
                    }
                }
                if expanded.contains("messages.send") && !sendTools.isEmpty { ToolPolicyRows(tools: sendTools) }
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
                SettingsRowDivider(leading: 60)
                SpotifyAccountRow()
            }
            SettingsSection(title: "Files") {
                SettingsRow(title: "Working folder", image: AppIcon.image(for: "com.apple.finder"), value: folder.isEmpty ? "Not set" : folder,
                            info: "File tools stay inside this folder. Coding tasks start here unless you choose another project.",
                            expanded: isOpen("files")) {
                    Button(folder.isEmpty ? "Choose folder" : "Change") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK { folder = panel.url?.path ?? "" }
                    }.buttonStyle(SpeekActionButtonStyle())
                }
                if expanded.contains("files") { ToolPolicyRows(tools: policies.tools(inGroup: "files")) }
            }
            SettingsSection(title: "Built-in", info: "Capabilities Speek always has. Choose when each one asks first.") {
                if CodexConnection.binary != nil {
                    SettingsRow(title: "Computer use", icon: "cursorarrow.rays",
                                info: "Clicking, typing, and navigating in apps and the browser for a task you asked for. Ask covers the whole task after one approval. Sensitive actions always ask.") {
                        ToolPolicyMenu(toolID: ToolPolicyStore.computerUseID, changesData: true, title: "Computer use")
                    }
                    SettingsRowDivider(leading: 60)
                }
                let media = policies.tools(inGroup: "media")
                SettingsRow(title: "Media keys", icon: "playpause", value: policies.summary(media),
                            info: "Play, pause, next, and previous in whatever is playing, and the Mac's volume.", expanded: isOpen("media")) { EmptyView() }
                if expanded.contains("media") { ToolPolicyRows(tools: media) }
                SettingsRowDivider(leading: 60)
                let web = policies.tools(inGroup: "web")
                SettingsRow(title: "Web search", icon: "globe", value: policies.summary(web), expanded: isOpen("web")) { EmptyView() }
                if expanded.contains("web") { ToolPolicyRows(tools: web) }
                SettingsRowDivider(leading: 60)
                let schedules = policies.tools(inGroup: "schedules")
                SettingsRow(title: "Schedules", icon: "calendar.badge.clock", value: policies.summary(schedules), expanded: isOpen("schedules")) { EmptyView() }
                if expanded.contains("schedules") { ToolPolicyRows(tools: schedules) }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    @ViewBuilder private func appRow(_ service: NativeAppService) -> some View {
        let installed = NativeAppTools.shared.isInstalled(service)
        let tools = policies.tools(inGroup: service.rawValue)
        SettingsRow(title: service.title, icon: service.symbol, image: AppIcon.image(for: service.bundleID),
                    value: installed ? (errors[service.rawValue] ?? policies.summary(tools)) : "Not installed", info: detail(service),
                    expanded: tools.isEmpty ? nil : isOpen(service.rawValue)) {
            busySwitch(service.rawValue, title: service.title, isOn: apps.contains(service), enabled: installed) { on in
                if on { try await NativeAppTools.shared.connect(service) } else { NativeAppTools.shared.disconnect(service) }
            }
        }
        if expanded.contains(service.rawValue) && !tools.isEmpty { ToolPolicyRows(tools: tools) }
    }

    @ViewBuilder private func organizerRow(_ service: OrganizerService, bundleID: String) -> some View {
        let status = organizer[service]
        let denied = status == .denied || status == .restricted
        let tools = status == .fullAccess && organizerEnabled.contains(service) ? policies.tools(inGroup: service.rawValue) : []
        SettingsRow(title: service.title, icon: service == .calendar ? "calendar" : "list.bullet.rectangle", image: AppIcon.image(for: bundleID),
                    value: denied ? "Access is off in System Settings" : (errors[service.rawValue] ?? policies.summary(tools)),
                    info: service == .calendar ? "Find availability and manage events." : "Find, create, and complete reminders.",
                    expanded: tools.isEmpty ? nil : isOpen(service.rawValue)) {
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
        if expanded.contains(service.rawValue) && !tools.isEmpty { ToolPolicyRows(tools: tools) }
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
        case .music: return "Current track, playback, and volume."
        case .spotify: return "Current track, playback, volume, and playing a link in the Spotify app. Works without Premium."
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

/// Signs in to the user's Spotify account for search, library, playlists, queue, and devices.
/// Uses the user's own Spotify app, so only its Client ID is needed (no secret).
private struct SpotifyAccountRow: View {
    @ObservedObject private var account = SpotifyAccount.shared
    @State private var setup = false
    @State private var clientID = ""
    @State private var error: String?

    var body: some View {
        SettingsRow(title: "Spotify account", image: AppIcon.image(for: "com.spotify.client"),
                    value: error ?? (account.isSignedIn ? "Signed in" + (account.displayName.map { " as " + $0 } ?? "") : "Search, library, playlists, queue, and devices"),
                    info: "Signs in with your own Spotify app. Create one at developer.spotify.com/dashboard: add the redirect URI http://127.0.0.1:43821/callback, select Web API, then paste its Client ID here. Queue and device control need Premium.") {
            if account.signingIn {
                ProgressView().controlSize(.small).frame(width: 38).accessibilityLabel("Signing in to Spotify")
            } else if account.isSignedIn {
                Button("Sign Out") { account.signOut() }.buttonStyle(SpeekActionButtonStyle())
            } else {
                HStack(spacing: 8) {
                    if !account.clientID.isEmpty {
                        Button("Client ID") { clientID = account.clientID; setup = true }.buttonStyle(SpeekActionButtonStyle())
                    }
                    Button("Sign In") {
                        if account.clientID.isEmpty { clientID = ""; setup = true } else { signIn() }
                    }
                        .buttonStyle(SpeekActionButtonStyle())
                        .popover(isPresented: $setup, arrowEdge: .bottom) { setupForm }
                }
            }
        }
    }

    private var setupForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spotify Client ID").font(.system(size: 13, weight: .semibold))
            Text("In your Spotify app's settings on developer.spotify.com, add the redirect URI below, then copy the Client ID.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(SpotifyAccount.redirectURI).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(SpotifyAccount.redirectURI, forType: .string) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }.buttonStyle(.plain).help("Copy redirect URI")
            }
            TextField("Client ID", text: $clientID).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
            HStack {
                Button("Open Dashboard") { NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!) }
                Spacer()
                Button("Sign In") { account.clientID = clientID; setup = false; signIn() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).count < 16)
            }
        }.padding(16).frame(width: 340)
    }

    private func signIn() {
        error = nil
        Task { @MainActor in
            do { try await account.signIn() } catch { self.error = error.localizedDescription }
        }
    }
}
