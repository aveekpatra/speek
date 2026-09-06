import Foundation
import os

/// Crash/kill-safe persistence for the in-progress live transcript.
///
/// While the user is dictating, the live transcript lives only in memory. If the app is
/// killed, crashes, or is rebuilt during development before the recording is committed,
/// that text is lost. This store mirrors the live transcript to a small file on disk —
/// atomically and debounced, off the main thread — and clears it once the recording has
/// been safely delivered/saved or explicitly cancelled.
///
/// So the rule is simple: if the recovery file still exists at launch, the previous
/// session died mid-dictation and its text can be recovered.
final class TranscriptRecoveryStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.whisperpro.transcript-recovery", qos: .utility)
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "TranscriptRecovery")

    // Debounce disk writes: at most one write per interval. On a crash we lose at most the
    // last fraction of a second of speech — never the whole transcript (the old behaviour).
    private let minWriteInterval: TimeInterval = 0.7
    private var latestText: String = ""
    private var writeScheduled = false
    private var lastWriteAt: Date = .distantPast

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("live-transcript-recovery.txt")
    }

    /// Record the current live transcript. Cheap — safe to call on every live update.
    func update(_ text: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.latestText = text
            guard !self.writeScheduled else { return }
            self.writeScheduled = true
            let delay = max(0, self.minWriteInterval - Date().timeIntervalSince(self.lastWriteAt))
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flush()
            }
        }
    }

    /// The recording was delivered/saved or cancelled — the transcript is safe elsewhere.
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.latestText = ""
            self.writeScheduled = false
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    /// Read a leftover transcript at launch. Returns nil when there is nothing to recover.
    func recoverPendingText() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Private

    private func flush() {
        writeScheduled = false
        lastWriteAt = Date()
        let text = latestText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            try Data(text.utf8).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist live transcript: \(error, privacy: .public)")
        }
    }
}
