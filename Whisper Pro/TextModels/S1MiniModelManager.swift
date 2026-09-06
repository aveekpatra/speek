import Foundation
import AppKit
import os

/// Downloads Superwhisper's open-weights S1-mini text normalizer (GGUF, q4_k_m).
@MainActor
final class S1MiniModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = S1MiniModelManager()
    static let modelName = "s1-mini"
    static let displayName = "S1-mini"
    static let sizeText = "484 MB"
    static let downloadURL = URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf")!

    @Published private(set) var downloadStatus: FluidAudioDownloadStatus?
    @Published private(set) var revision = 0

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "S1MiniModelManager")
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    nonisolated static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speek/models/s1-mini", isDirectory: true)
    }

    nonisolated static var modelFileURL: URL {
        modelDirectory.appendingPathComponent("s1-mini-q4_k_m.gguf")
    }

    var isDownloaded: Bool {
        _ = revision
        return FileManager.default.fileExists(atPath: Self.modelFileURL.path)
    }

    var isDownloading: Bool { downloadStatus != nil }

    func download() {
        guard !isDownloaded, task == nil else { return }
        downloadStatus = FluidAudioDownloadStatus(fractionCompleted: 0, message: String(localized: "Downloading S1-mini..."))
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.downloadTask(with: Self.downloadURL)
        self.task = task
        task.resume()
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        downloadStatus = nil
    }

    func delete() {
        try? FileManager.default.removeItem(at: Self.modelDirectory)
        revision += 1
        S1MiniService.shared.unload()
    }

    func showInFinder() {
        if FileManager.default.fileExists(atPath: Self.modelFileURL.path) {
            NSWorkspace.shared.selectFile(Self.modelFileURL.path, inFileViewerRootedAtPath: "")
        }
    }

    // MARK: URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let written = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        Task { @MainActor in
            self.downloadStatus = FluidAudioDownloadStatus(fractionCompleted: fraction, message: "Downloading S1-mini: \(written)")
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destination = Self.modelFileURL
        do {
            try FileManager.default.createDirectory(at: Self.modelDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            Task { @MainActor in self.logger.error("S1-mini install failed: \(error, privacy: .public)") }
        }
        Task { @MainActor in
            self.task = nil
            self.downloadStatus = nil
            self.revision += 1
            NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.logger.error("S1-mini download failed: \(error, privacy: .public)")
            self.task = nil
            self.downloadStatus = nil
        }
    }
}
