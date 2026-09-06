import Foundation
import FluidAudio
import os

/// Offline transcription with NVIDIA Canary 1B v2 through FluidAudio's `CanaryManager`.
final class CanaryTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "CanaryTranscriptionService")
    private var models: CanaryModels?
    private var loadingTask: Task<CanaryModels, Error>?
    private var languageTokenCache: [String: Int32] = [:]

    enum ServiceError: LocalizedError {
        case modelNotDownloaded

        var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return String(localized: "Canary 1B v2 is not downloaded yet. Download it in Models library.")
            }
        }
    }

    func loadModel() async throws {
        _ = try await loadedModels()
    }

    private func loadedModels() async throws -> CanaryModels {
        if let models { return models }
        if let loadingTask { return try await loadingTask.value }
        let directory = CanaryModelManager.modelDirectory
        guard CanaryModels.modelsExist(at: directory, precision: CanaryModelManager.precision) else {
            throw ServiceError.modelNotDownloaded
        }
        await VoiceModelLoadState.shared.beginLoading("Canary 1B v2")
        let task = Task.detached(priority: .userInitiated) {
            try CanaryModels.load(from: directory, precision: CanaryModelManager.precision)
        }
        loadingTask = task
        do {
            let loaded = try await task.value
            models = loaded
            loadingTask = nil
            await VoiceModelLoadState.shared.finishLoading("Canary 1B v2", success: true)
            return loaded
        } catch {
            loadingTask = nil
            await VoiceModelLoadState.shared.finishLoading("Canary 1B v2", success: false)
            throw error
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        let models = try await loadedModels()
        let prompt = prompt(for: context.language, models: models)
        let manager = CanaryManager(models: models, prompt: prompt)
        let start = CFAbsoluteTimeGetCurrent()
        let text = try await manager.transcribe(audioURL: audioURL)
        logger.info("Canary transcribed in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start))s")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Canary prompt: ▁ <|startofcontext|> <|startoftranscript|> <|emo:undefined|> <|src|> <|tgt|> <|pnc|> <|noitn|> <|notimestamp|> <|nodiarize|>
    private func prompt(for languageCode: String?, models: CanaryModels) -> [Int32] {
        var prompt = CanaryConfig.promptEnTranscribePnc
        guard let code = languageCode?.lowercased(), code != "auto", code != "en" else { return prompt }
        let token: Int32
        if let cached = languageTokenCache[code] {
            token = cached
        } else {
            var found: Int32?
            for id in 0..<400 {
                if models.tokenizer.rawToken(for: id) == "<|\(code)|>" {
                    found = Int32(id)
                    break
                }
            }
            guard let found else { return prompt }
            languageTokenCache[code] = found
            token = found
        }
        prompt[4] = token
        prompt[5] = token
        return prompt
    }

    func unload() {
        models = nil
    }
}
