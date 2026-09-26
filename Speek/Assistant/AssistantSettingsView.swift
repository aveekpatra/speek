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
    static let tabs = ["General", "Dictation", "Privacy", "Permissions"]
    @ObservedObject private var navigation = SpeekMainWindow.shared
    @ObservedObject private var permissions = PermissionsCenter.shared
    @ObservedObject private var memory = AssistantMemory.shared
    @ObservedObject private var recovery = RecordingRecovery.shared
    @AppStorage("speek.assistant.useFocusedContext") private var focusedContext = true
    @AppStorage("speek.dictation.doubleTapHandsFree") private var handsFree = false
    @AppStorage("speek.voice.recordingRecovery") private var recoveryEnabled = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?
    @State private var confirmingDeleteRecordings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings").font(.system(size: 25, weight: .semibold))
                    Text("Make Speek work the way you do.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                tabBar
                switch navigation.settingsTab {
                case "Dictation": dictation
                case "Privacy": privacy
                case "Permissions": permissionList
                default: general
                }
                if let settingsError {
                    Label(settingsError, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(24)
        }
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
        .confirmationDialog("Delete all recovery recordings?", isPresented: $confirmingDeleteRecordings, titleVisibility: .visible) {
            Button("Delete recordings", role: .destructive) { recovery.deleteAll() }
        } message: { Text("The saved audio will be removed from this Mac. This cannot be undone.") }
    }

    private var tabBar: some View {
        PillTabs(items: Self.tabs, selection: $navigation.settingsTab)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "Shortcut") {
                SettingsRow(title: "Speak shortcut", icon: "keyboard", info: "Hold to speak. Release to finish.") {
                    ShortcutRecorder(action: .primaryRecording)
                }
                SettingsRowDivider(leading: 60)
                SettingsRow(title: "Double-tap for hands-free", icon: "hand.tap.fill", info: "Double-tap the shortcut to keep recording. Press it again to finish.") {
                    Toggle("Double-tap for hands-free", isOn: $handsFree).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsSection(title: "Context") {
                SettingsRow(title: "Screen context", icon: "viewfinder", info: "Include the screen and selected text in agent requests.") {
                    Toggle("Screen context", isOn: $focusedContext).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsSection(title: "Startup") {
                SettingsRow(title: "Launch at login", icon: "power") {
                    Toggle("Launch at login", isOn: $loginEnabled).labelsHidden().toggleStyle(.switch)
                        .onChange(of: loginEnabled) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch { settingsError = error.localizedDescription }
                        }
                }
            }
            SettingsSection(title: "About") {
                SettingsRow(title: "Version", icon: "tag.fill", info: "GPL-3.0. Based on Whisper Pro and VoiceInk.") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.8")
                        .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 28) {
            VoiceCaptureSettingsView(isRecording: AssistantController.shared.recording)
            DictationSettingsView()
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "History") {
                SettingsRow(title: "Save history on this Mac", icon: "clock.arrow.circlepath", info: "Saves chats, completed requests, and the latest 500 dictations. Turning it off stops saving and recalling past events. Existing entries are kept.") {
                    Toggle("Save history on this Mac", isOn: $memory.saveHistory).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsSection(title: "Recording recovery") {
                SettingsRow(title: "Keep failed recordings temporarily", icon: "waveform.badge.exclamationmark", value: memory.saveHistory ? nil : "Paused while history is off",
                            info: "Keeps up to 5 failed recordings (100 MB) for 24 hours so you can retry them from Dictation history. Removed after successful delivery.") {
                    Toggle("Keep failed recordings temporarily", isOn: $recoveryEnabled).labelsHidden().toggleStyle(.switch)
                }
                if !recovery.recordings.isEmpty {
                    SettingsRowDivider(leading: 60)
                    SettingsRow(title: "Saved recordings", icon: "trash.fill", value: "\(recovery.recordings.count) waiting in Dictation history") {
                        Button("Delete recordings") { confirmingDeleteRecordings = true }.buttonStyle(SpeekActionButtonStyle())
                    }
                }
            }
        }
    }

    private var permissionList: some View {
        SettingsSection(title: "Permissions") {
            permission("Microphone", icon: "mic.fill", info: "Record spoken requests and dictation.", granted: permissions.microphoneGranted, action: permissions.allowMicrophone)
            SettingsRowDivider(leading: 60)
            permission("Accessibility", icon: "accessibility", info: "Use the global shortcut, focused fields, and selected text.", granted: permissions.accessibilityTrusted, action: permissions.allowAccessibility)
            SettingsRowDivider(leading: 60)
            permission("Screen Recording", icon: "rectangle.inset.filled", value: permissions.screenCaptureError, info: "See the screen and capture regions you circle.", granted: permissions.screenCaptureGranted, action: permissions.allowScreenCapture)
        }
    }

    private func permission(_ title: String, icon: String, value: String? = nil, info: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingsRow(title: title, icon: icon, value: value, info: info) {
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
}
