import Foundation
import Combine
import os

/// Implements Advanced settings > "Voice model active duration": after the recorder
/// goes idle, wait the configured time and free every loaded model (voice and S1-mini).
/// A new recording cancels the countdown. "Always loaded" never unloads;
/// "Unload immediately" unloads as soon as the transcription finished.
@MainActor
final class ModelIdleUnloader {
    static let shared = ModelIdleUnloader()

    private var observer: AnyCancellable?
    private var countdown: Task<Void, Never>?
    private weak var engine: SpeekEngine?
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "ModelIdleUnloader")

    private init() {}

    func attach(engine: SpeekEngine) {
        self.engine = engine
        observer = engine.$recordingState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .idle { self.scheduleUnload() } else { self.cancel() }
            }
    }

    private func cancel() {
        countdown?.cancel()
        countdown = nil
    }

    private func scheduleUnload() {
        cancel()
        let duration = SpeekSettings.shared.modelActiveDuration
        guard duration != .always else { return }
        let seconds = max(0, duration.rawValue)
        countdown = Task { @MainActor [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled, let self, let engine = self.engine, engine.recordingState == .idle else { return }
            self.logger.notice("Idle for \(seconds)s: unloading models")
            await engine.serviceRegistry.unloadAllModels()
            engine.whisperModelManager.unloadModel()
            S1MiniService.shared.unload()
        }
    }
}
