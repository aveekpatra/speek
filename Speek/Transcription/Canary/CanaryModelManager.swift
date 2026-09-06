import Foundation
import FluidAudio
import AppKit
import os

/// NVIDIA Canary 1B v2 (CoreML int4 build from FluidInference): 25 European languages.
@MainActor
final class CanaryModelManager: ObservableObject {
    static let shared = CanaryModelManager()
    static let modelName = "canary-1b-v2"
    static let precision: CanaryPrecision = .int4

    @Published private(set) var downloadStatus: FluidAudioDownloadStatus?
    @Published private(set) var revision = 0

    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "CanaryModelManager")
    private var downloadTask: Task<Void, Never>?

    private init() {}

    nonisolated static var modelDirectory: URL {
        AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
            .appendingPathComponent(Repo.canary1bV2.folderName, isDirectory: true)
    }

    var isDownloaded: Bool {
        _ = revision
        return CanaryModels.modelsExist(at: Self.modelDirectory, precision: Self.precision)
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
                _ = try await CanaryModels.download(precision: Self.precision, progressHandler: { progress in
                    Task { @MainActor [weak self] in
                        self?.downloadStatus = FluidAudioDownloadStatus(
                            fractionCompleted: min(max(progress.fractionCompleted, 0), 1),
                            message: Self.message(for: progress)
                        )
                    }
                })
            } catch {
                self?.logger.error("Canary download failed: \(error, privacy: .public)")
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
