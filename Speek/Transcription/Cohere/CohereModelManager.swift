import Foundation
import FluidAudio
import AppKit
import os

/// Downloads, deletes and locates the Cohere Transcribe CoreML build
/// (`FluidInference/cohere-transcribe-03-2026-coreml`, q8 encoder + v2 decoder).
@MainActor
final class CohereModelManager: ObservableObject {
    static let shared = CohereModelManager()
    static let modelName = "cohere-transcribe-03-2026"

    @Published private(set) var downloadStatus: FluidAudioDownloadStatus?
    @Published private(set) var revision = 0

    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "CohereModelManager")
    private var downloadTask: Task<Void, Never>?

    private init() {}

    /// Parent directory that FluidAudio uses for all repos (same root as Parakeet).
    nonisolated static var modelsRootDirectory: URL {
        AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
    }

    /// Directory holding `cohere_encoder.mlmodelc`, the v2 decoder and `vocab.json`.
    nonisolated static var modelDirectory: URL {
        modelsRootDirectory.appendingPathComponent(Repo.cohereTranscribeCoreml.folderName, isDirectory: true)
    }

    nonisolated static var requiredFiles: [String] {
        Array(ModelNames.CohereTranscribe.requiredModels)
    }

    var isDownloaded: Bool {
        _ = revision
        return Self.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: Self.modelDirectory.appendingPathComponent($0).path)
        }
    }

    var isDownloading: Bool { downloadStatus != nil }

    func download() {
        guard !isDownloaded, downloadTask == nil else { return }
        downloadStatus = FluidAudioDownloadStatus(fractionCompleted: 0, message: String(localized: "Preparing download..."))
        downloadTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.downloadTask = nil
                    self?.downloadStatus = nil
                    self?.revision += 1
                    self?.onModelsChanged?()
                }
            }
            do {
                try await ModelHub.download(
                    .cohereTranscribeCoreml,
                    to: Self.modelsRootDirectory,
                    progressHandler: { progress in
                        Task { @MainActor [weak self] in
                            self?.downloadStatus = FluidAudioDownloadStatus(
                                fractionCompleted: min(max(progress.fractionCompleted, 0), 1),
                                message: Self.message(for: progress)
                            )
                        }
                    }
                )
            } catch {
                self?.logger.error("Cohere download failed: \(error, privacy: .public)")
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func delete() {
        try? FileManager.default.removeItem(at: Self.modelDirectory)
        revision += 1
        onModelsChanged?()
    }

    func showInFinder() {
        let url = Self.modelDirectory
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        }
    }

    private static func message(for progress: DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            return String(localized: "Listing files from repository...")
        case .downloading(let completed, let total):
            guard total > 0 else { return String(localized: "Downloading...") }
            return String(format: String(localized: "Downloading model files: %lld/%lld"), Int64(completed), Int64(total))
        case .compiling(let name):
            return String(format: String(localized: "Compiling %@"), name.replacingOccurrences(of: ".mlmodelc", with: ""))
        }
    }
}
