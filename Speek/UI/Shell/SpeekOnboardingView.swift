import SwiftUI
import AVFoundation
import AppKit

/// First-run flow: welcome, permissions, voice model, shortcut.
struct SpeekOnboardingView: View {
    @Binding var hasCompleted: Bool
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @ObservedObject private var cohereModelManager = CohereModelManager.shared
    @Environment(\.colorScheme) private var scheme

    private enum Step: Int, CaseIterable { case welcome, permissions, model, shortcut }
    @State private var step: Step = .welcome
    @ObservedObject private var permissions = PermissionsCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 720, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissionsStep
        case .model: modelStep
        case .shortcut: shortcutStep
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Speek")
                .font(.system(size: 30, weight: .bold))
            Text("Press a shortcut, speak, and the text lands wherever your cursor is.\nEverything runs on your Mac. Nothing is sent anywhere.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var permissionsStep: some View {
        stepLayout(title: "Permissions", subtitle: "Speek needs two permissions to record and to type for you. Each button opens exactly what macOS needs.") {
            SpeekGroup {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records your voice for transcription.",
                    granted: permissions.microphoneGranted,
                    buttonTitle: permissions.microphoneStatus == .notDetermined ? "Allow" : "Open Settings",
                    action: permissions.allowMicrophone
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "Pastes the text into the app you are using and presses Return when you ask for it. Turn on the switch next to Speek in the pane that opens.",
                    granted: permissions.accessibilityTrusted,
                    buttonTitle: "Open Settings",
                    action: permissions.allowAccessibility
                )
            }
        }
    }

    private var modelStep: some View {
        stepLayout(title: "Choose a voice model", subtitle: "Models are downloaded once and run offline. You can add more later in Models library.") {
            SpeekGroup {
                modelRow(
                    title: "Parakeet V3",
                    detail: "Recommended. Very fast, 25 European languages. 494 MB.",
                    availability: parakeetAvailability,
                    download: {
                        if let model = parakeetModel { Task { await fluidAudioModelManager.downloadFluidAudioModel(model) } }
                    }
                )
                modelRow(
                    title: "Cohere Transcribe",
                    detail: "Most accurate. 14 languages including Japanese, Chinese, Korean and Arabic. 2.1 GB.",
                    availability: cohereAvailability,
                    download: { cohereModelManager.download() }
                )
                modelRow(
                    title: "Apple Speech",
                    detail: "Built into macOS. Good for a quick start.",
                    availability: .downloaded,
                    download: {}
                )
            }
        }
    }

    private var shortcutStep: some View {
        stepLayout(title: "Your shortcut", subtitle: "Press it once to start recording and again to stop. Change it any time in Configuration.") {
            SpeekGroup {
                SpeekRow("Toggle Recording", subtitle: "Starts and stops recordings") {
                    ShortcutRecorder(action: .primaryRecording)
                }
                SpeekRow("Cancel Recording", subtitle: "Discards the active recording") {
                    SpeekKeycap(text: "esc")
                }
            }
            Text("Tip: hold Shift while stopping a recording to press Return automatically after the text is pasted.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pieces

    private func stepLayout<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 24, weight: .bold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            content()
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Availability { case downloaded, downloading(Double), notDownloaded }

    private func modelRow(title: String, detail: String, availability: Availability, download: @escaping () -> Void) -> some View {
        SpeekRow(LocalizedStringKey(title), subtitle: LocalizedStringKey(detail)) {
            switch availability {
            case .downloaded:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13, weight: .medium))
            case .downloading(let fraction):
                HStack(spacing: 8) {
                    Text("\(Int(fraction * 100))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                    ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
                }
            case .notDownloaded:
                Button("Download", action: download).buttonStyle(.glass)
            }
        }
    }

    private var parakeetModel: FluidAudioModel? {
        transcriptionModelManager.allAvailableModels.compactMap { $0 as? FluidAudioModel }.first { $0.name == "parakeet-tdt-0.6b-v3" }
    }

    private var parakeetAvailability: Availability {
        guard let model = parakeetModel else { return .notDownloaded }
        if let status = fluidAudioModelManager.downloadStatus(for: model) { return .downloading(status.fractionCompleted) }
        return fluidAudioModelManager.isFluidAudioModelDownloaded(model) ? .downloaded : .notDownloaded
    }

    private var cohereAvailability: Availability {
        if let status = cohereModelManager.downloadStatus { return .downloading(status.fractionCompleted) }
        return cohereModelManager.isDownloaded ? .downloaded : .notDownloaded
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    .buttonStyle(.glass)
            }
            Button(step == .shortcut ? "Start using Speek" : "Continue") { advance() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private func advance() {
        if step == .shortcut {
            pickDefaultModelIfNeeded()
            hasCompleted = true
            return
        }
        step = Step(rawValue: step.rawValue + 1) ?? .shortcut
    }

    private func pickDefaultModelIfNeeded() {
        guard transcriptionModelManager.currentTranscriptionModel == nil else { return }
        transcriptionModelManager.refreshAllAvailableModels()
        let preferred = ["parakeet-tdt-0.6b-v3", CohereModelManager.modelName, "apple-speech"]
        for name in preferred {
            if let model = transcriptionModelManager.usableModels.first(where: { $0.name == name }) {
                transcriptionModelManager.setDefaultTranscriptionModel(model)
                return
            }
        }
    }
}
