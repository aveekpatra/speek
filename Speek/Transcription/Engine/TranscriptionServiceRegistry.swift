import Foundation
import SwiftUI
import SwiftData
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()
    private(set) lazy var cohereTranscriptionService = CohereTranscriptionService()
    private(set) lazy var canaryTranscriptionService = CanaryTranscriptionService()

    init(modelProvider: any WhisperModelProvider, modelsDirectory: URL, modelContext: ModelContext) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
    }

    /// Drops every loaded voice model. Only touches services that were created.
    func unloadAllModels() async {
        await fluidAudioTranscriptionService.unload()
        cohereTranscriptionService.unload()
        canaryTranscriptionService.unload()
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        OnlineOnlyTranscriptionService()
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext = .currentDefaults) async throws -> String {
        return try await CloudActionClient.transcribe(audioURL)
    }

    /// Creates a streaming or file-based session for the resolved transcription configuration.
    func createSession(for configuration: TranscriptionRuntimeConfiguration, onPartialTranscript: ((String, String) -> Void)? = nil) -> TranscriptionSession {
        FileTranscriptionSession(service: OnlineOnlyTranscriptionService())
    }

    /// Whether the resolved transcription configuration should use real-time transcription.
    func shouldUseRealtimeTranscription(for configuration: TranscriptionRuntimeConfiguration) -> Bool {
        false
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}

private struct OnlineOnlyTranscriptionService: TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        try await CloudActionClient.transcribe(audioURL)
    }
}
