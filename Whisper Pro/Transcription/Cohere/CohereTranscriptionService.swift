import Foundation
import CoreML
import FluidAudio
import os

/// Offline transcription through FluidAudio's `CoherePipeline`.
final class CohereTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "CohereTranscriptionService")
    private let pipeline = CoherePipeline()
    private var loadedModels: CoherePipeline.LoadedModels?
    private var loadingTask: Task<CoherePipeline.LoadedModels, Error>?

    enum ServiceError: LocalizedError {
        case modelNotDownloaded

        var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return String(localized: "Cohere Transcribe is not downloaded yet. Download it in Models library.")
            }
        }
    }

    func loadModel() async throws {
        _ = try await models()
    }

    private func models() async throws -> CoherePipeline.LoadedModels {
        if let loadedModels { return loadedModels }
        if let loadingTask { return try await loadingTask.value }
        let directory = CohereModelManager.modelDirectory
        let allPresent = CohereModelManager.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        guard allPresent else { throw ServiceError.modelNotDownloaded }

        let computeUnits: MLComputeUnits = {
            switch UserDefaults.standard.string(forKey: "speek.cohereComputeUnits") {
            case "gpu": return .cpuAndGPU
            case "ane": return .cpuAndNeuralEngine
            default: return .all
            }
        }()
        let loadStart = CFAbsoluteTimeGetCurrent()
        await VoiceModelLoadState.shared.beginLoading("Cohere Transcribe")
        let task = Task {
            let loaded = try await CoherePipeline.loadModels(
                encoderDir: directory,
                decoderDir: directory,
                vocabDir: directory,
                decoderVariant: .v2,
                computeUnits: computeUnits
            )
            self.logger.notice("Cohere models loaded in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - loadStart))s (compute units \(computeUnits.rawValue))")
            return loaded
        }
        loadingTask = task
        do {
            let models = try await task.value
            loadedModels = models
            loadingTask = nil
            await VoiceModelLoadState.shared.finishLoading("Cohere Transcribe", success: true)
            return models
        } catch {
            loadingTask = nil
            await VoiceModelLoadState.shared.finishLoading("Cohere Transcribe", success: false)
            throw error
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        let models = try await models()
        let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)
        let language = CohereAsrConfig.Language(rawValue: context.language ?? "") ?? .english
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await pipeline.transcribeLong(audio: samples, models: models, language: language)
        logger.notice("Cohere transcribed \(samples.count / 16000)s of audio in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start))s (encoder \(String(format: "%.2f", result.encoderSeconds))s, decoder \(String(format: "%.2f", result.decoderSeconds))s, \(result.tokenIds.count) tokens)")
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        loadedModels = nil
    }
}
