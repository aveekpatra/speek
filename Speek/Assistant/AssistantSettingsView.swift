import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class AssistantSettingsWindow {
    static let shared = AssistantSettingsWindow()
    func show() {
        SpeekMainWindow.shared.showSettings()
    }
}

struct AssistantSettingsView: View {
    @State private var tab: String
    private let embedded: Bool
    init(initialSection: String = "General", embedded: Bool = false) {
        _tab = State(initialValue: initialSection)
        self.embedded = embedded
    }
    @ObservedObject private var permissions = PermissionsCenter.shared
    @ObservedObject private var memory = AssistantMemory.shared
    @ObservedObject private var history = ActionThreadStore.shared
    @AppStorage("speek.assistant.useFocusedContext") private var focusedContext = true
    @AppStorage("speek.assistant.readReplies") private var readReplies = false
    @AppStorage("speek.actions.projectFolder") private var folder = ""
    @AppStorage("speek.voice.playbackRate") private var playbackRate = 1.0
    @State private var fact = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
            HStack {
                Text("Speek").font(.system(size: 24, weight: .semibold))
                Spacer()
                Button("Show assistant") { AssistantController.shared.show(typing: true) }
                    .buttonStyle(SpeekActionButtonStyle())
            }.padding(24)
            Picker("Settings", selection: $tab) {
                ForEach(["General", "Connections", "Memory", "Activity"], id: \.self) { Text($0 == "Connections" ? "Models & Voice" : $0).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case "Connections": ActionConnectionsView()
                    case "Memory": memorySettings
                    case "Activity": activity
                    default: general
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: embedded ? 0 : 640, maxWidth: .infinity, minHeight: embedded ? 0 : 570, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            Task { await permissions.refreshScreenCapture(force: true) }
        }
        .task {
            await permissions.refreshScreenCapture()
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings").font(.system(size: 25, weight: .semibold))
                Text("Make Speek work the way you do.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            settingsGroup("Voice and context") {
                settingsRow("Speak shortcut", icon: "keyboard", detail: "Hold to speak. Release to finish.") {
                    ShortcutRecorder(action: .primaryRecording)
                }
                settingsDivider
                settingsRow("Screen context", icon: "viewfinder", detail: "Include the screen and selected text in agent requests.") {
                    Toggle("Screen context", isOn: $focusedContext).labelsHidden().toggleStyle(.switch)
                }
                settingsDivider
                settingsRow("Spoken replies", icon: "speaker.wave.2.fill", detail: "Read responses aloud. Choose a voice in Models & Voice.") {
                    Toggle("Spoken replies", isOn: $readReplies).labelsHidden().toggleStyle(.switch)
                }
            }
            settingsGroup("Playback") {
                settingsRow("Speaking speed", icon: "speedometer", detail: "Adjust the speed of spoken replies.") {
                    Picker("Speaking speed", selection: $playbackRate) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in Text(String(format: "%g x", rate)).tag(rate) }
                    }.labelsHidden().fixedSize()
                }
            }
            VoiceCaptureSettingsView(isRecording: AssistantController.shared.recording)
            DictationSettingsView()
            RecordingRecoveryView()
            settingsGroup("Startup") {
                settingsRow("Launch at login", icon: "power", detail: "Keep Speek available in the menu bar.") {
                    Toggle("Launch at login", isOn: $loginEnabled).labelsHidden().toggleStyle(.switch)
                        .onChange(of: loginEnabled) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch { settingsError = error.localizedDescription }
                        }
                }
            }
            settingsGroup("Permissions") {
                permission("Microphone", icon: "mic.fill", detail: "Record spoken requests and dictation.", granted: permissions.microphoneGranted, action: permissions.allowMicrophone)
                settingsDivider
                permission("Accessibility", icon: "accessibility", detail: "Use the global shortcut, focused fields, and selected text.", granted: permissions.accessibilityTrusted, action: permissions.allowAccessibility)
                settingsDivider
                permission("Screen Recording", icon: "rectangle.inset.filled", detail: permissions.screenCaptureError ?? "See the screen and capture regions you circle.", granted: permissions.screenCaptureGranted, action: permissions.allowScreenCapture)
            }
            settingsGroup("Files") {
                settingsRow("Working folder", icon: "folder.fill", detail: folder.isEmpty ? "Choose where Speek can work with files." : folder) {
                    Button("Choose folder") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK { folder = panel.url?.path ?? "" }
                    }.buttonStyle(SpeekActionButtonStyle())
                }
            }
            if let settingsError {
                Label(settingsError, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Speek " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.8"))
                    .font(.system(size: 12, weight: .medium))
                Text("Closing this window keeps Speek available in the menu bar.")
                Text("GPL-3.0. Based on Whisper Pro and VoiceInk.")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 60).padding(.trailing, 16)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            VStack(spacing: 0, content: content).settingsSurface()
        }
    }

    private func settingsRow<Control: View>(_ title: String, icon: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(.white).frame(width: 28, height: 32)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    rowLabel(title, detail: detail).frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                    control().fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    rowLabel(title, detail: detail)
                    control().fixedSize()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(16)
    }

    private func rowLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func permission(_ title: String, icon: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        settingsRow(title, icon: icon, detail: detail) {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.white)
                    .accessibilityLabel(title + " allowed")
            } else {
                Button("Allow", action: action).buttonStyle(SpeekActionButtonStyle())
                    .accessibilityLabel("Allow " + title)
            }
        }
    }
    private var memorySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Remember conversations on this Mac", isOn: $memory.saveHistory)
            Text("Saved facts and relevant past requests are included with new requests. Screen images are sent only when attached and are not saved to history.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Something Speek should remember", text: $fact).textFieldStyle(.roundedBorder)
                Button("Save") { memory.remember(fact); fact = "" }.disabled(fact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(memory.facts) { item in
                HStack(alignment: .top) {
                    Text(item.text).textSelection(.enabled)
                    Spacer()
                    Button("Forget") { memory.remove(item.id) }.font(.caption)
                }
                Divider()
            }
            if memory.facts.isEmpty { Text("Say \"Remember that...\" to save a fact.").foregroundStyle(.secondary) }
        }.font(.system(size: 13)).toggleStyle(.switch)
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your past requests. Resume from the floating assistant whenever you need to.")
                .font(.caption).foregroundStyle(.secondary)
            if history.threads.isEmpty { Text("No saved requests yet.").foregroundStyle(.secondary) }
            ForEach(history.threads) { thread in
                DisclosureGroup {
                    ForEach(thread.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Speek").font(.caption).foregroundStyle(.secondary)
                            Text(message.text).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                    HStack {
                        Button("Resume") { AssistantController.shared.resume(thread) }
                        Spacer()
                        Button("Forget conversation", role: .destructive) { history.delete(thread.id) }
                    }
                } label: { Text(thread.title).lineLimit(1) }
                Divider()
            }
        }.font(.system(size: 13)).toggleStyle(.switch)
    }
}
