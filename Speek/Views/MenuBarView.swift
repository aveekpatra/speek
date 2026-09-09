import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Menu bar menu: Toggle Recording, Transcribe File, History,
/// Settings, microphone and mode pickers, version, updates, quit.
struct MenuBarView: View {
    @ObservedObject private var agentCenter = AgentUpdateCenter.shared
    @EnvironmentObject var engine: SpeekEngine
    @EnvironmentObject var recorderUIManager: RecorderUIManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @ObservedObject private var modeManager = ModeManager.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = false

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Version \(short)"
    }

    var body: some View {
        Group {
            if hasCompletedOnboardingV2 {
                mainMenu
            } else {
                Button("Finish setting up Speek") { menuBarManager.focusMainWindow() }
                Divider()
                Button("Quit Speek") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private var mainMenu: some View {
        Group {
            Button(engine.recordingState == .recording ? "Stop Recording" : "Toggle Recording") {
                recorderUIManager.handleToggleRecorderPanelNotification()
            }

            Button("Transcribe File...") { transcribeFile() }

            if !agentCenter.pending.isEmpty {
                Button(agentCenter.pending.count == 1 ? "Show agent reply" : "Show agent replies (\(agentCenter.pending.count) waiting)") {
                    agentCenter.showPendingPanel()
                }
            }

            Button("History...") { openPage(.history) }
                .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Settings...") { openPage(.configuration) }
            PermissionsMenuItem()
                .keyboardShortcut(",", modifiers: .command)

            Divider()

            Menu(currentMicrophoneName) {
                Button {
                    audioDeviceManager.selectInputMode(.systemDefault)
                } label: {
                    Text(audioDeviceManager.inputMode == .systemDefault ? "System default  ✓" : "System default")
                }
                Divider()
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button {
                        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
                    } label: {
                        let active = audioDeviceManager.inputMode == .custom && audioDeviceManager.getCurrentDevice() == device.id
                        Text(active ? "\(device.name)  ✓" : device.name)
                    }
                }
            }

            Menu(modeManager.currentEffectiveConfiguration?.name ?? "Voice to text") {
                ForEach(modeManager.enabledConfigurations) { config in
                    Button {
                        modeManager.setActiveConfiguration(config)
                    } label: {
                        let active = modeManager.currentEffectiveConfiguration?.id == config.id
                        Text(active ? "\(config.name)  ✓" : config.name)
                    }
                }
                Divider()
                Button("Manage Modes...") { openPage(.modes) }
            }

            Divider()

            Text(versionText)
            Button("Check for Updates...") { updaterViewModel.checkForUpdates() }
                .disabled(!updaterViewModel.canCheckForUpdates)

            Divider()

            Button("Quit Speek") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .task { audioDeviceManager.loadAvailableDevices() }
    }

    private var currentMicrophoneName: String {
        let id = audioDeviceManager.getCurrentDevice()
        let name = audioDeviceManager.getDeviceName(deviceID: id) ?? "No microphone"
        return audioDeviceManager.inputMode == .custom ? name : "\(name) (Default)"
    }

    private func openPage(_ page: SpeekPage) {
        menuBarManager.focusMainWindow()
        SpeekNavigation.shared.open(page)
    }

    private func transcribeFile() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .wav, .mp3, .aiff, UTType("com.apple.m4a-audio") ?? .audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an audio or video file to transcribe"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            NotificationManager.shared.showNotification(title: String(localized: "Pick a voice model in Models library first"), type: .error)
            return
        }
        let service = AudioTranscriptionService(
            modelContext: engine.modelContext,
            serviceRegistry: engine.serviceRegistry,
            enhancementService: engine.enhancementService
        )
        Task {
            do {
                _ = try await service.retranscribeAudio(from: url, using: model)
                NotificationManager.shared.showNotification(title: String(localized: "Transcript saved to History"), type: .success)
                openPage(.history)
            } catch {
                NotificationManager.shared.showNotification(title: error.localizedDescription, type: .error)
            }
        }
    }
}
