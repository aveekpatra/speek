import Foundation
import Combine

struct RecoverableRecording: Codable, Identifiable {
    var id: UUID
    var appName: String
    var createdAt: Date
    var byteCount: Int64
    var sourcePath: String
    var fileExtension: String
    var fileName: String { id.uuidString + "." + fileExtension }
}

@MainActor
final class RecordingRecovery: ObservableObject {
    static let shared = RecordingRecovery()
    static let retention: TimeInterval = 24 * 60 * 60
    static let maximumCount = 5
    static let maximumBytes: Int64 = 100 * 1024 * 1024
    @Published private(set) var recordings: [RecoverableRecording] = []
    @Published private(set) var error: String?
    private let directory: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private var loadFailed = false
    private var cleanupTimer: Timer?
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    var enabled: Bool {
        defaults.bool(forKey: "speek.voice.recordingRecovery") && (defaults.object(forKey: "speek.assistant.saveHistory") as? Bool ?? true)
    }

    init(directory: URL? = nil, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek/recording-recovery", isDirectory: true)
        self.defaults = defaults; self.now = now
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                recordings = try JSONDecoder().decode([RecoverableRecording].self, from: Data(contentsOf: indexURL))
                recordings = recordings.filter { ["wav", "m4a", "mp3", "caf"].contains($0.fileExtension) }
            } catch { loadFailed = true; self.error = "Recording recovery could not be loaded. Existing files were preserved." }
        }
        cleanup()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cleanup() }
        }
    }

    deinit { cleanupTimer?.invalidate() }

    /// Returns nil when recovery is disabled, private history is off, or the backup cannot be made.
    @discardableResult func save(audioURL: URL, appName: String) -> UUID? {
        guard enabled, !loadFailed else { return nil }
        cleanup()
        let source = audioURL.standardizedFileURL.path
        if let existing = recordings.first(where: { $0.sourcePath == source }) { return existing.id }
        let ext = audioURL.pathExtension.lowercased()
        guard ["wav", "m4a", "mp3", "caf"].contains(ext) else { error = "This recording format cannot be backed up."; return nil }
        var pendingCopy: URL?
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0, size <= Self.maximumBytes else { error = "This recording is too large for recovery storage."; return nil }
            try prepareDirectory()
            let item = RecoverableRecording(id: UUID(), appName: String(appName.prefix(200)), createdAt: now(), byteCount: size, sourcePath: source, fileExtension: ext)
            let destination = directory.appendingPathComponent(item.fileName)
            try FileManager.default.copyItem(at: audioURL, to: destination)
            pendingCopy = destination
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            var next = recordings + [item]
            while next.count > Self.maximumCount || next.reduce(Int64(0), { $0 + $1.byteCount }) > Self.maximumBytes { next.removeFirst() }
            do { try writeIndex(next) } catch { try? FileManager.default.removeItem(at: destination); throw error }
            removeFiles(recordings.filter { old in !next.contains(where: { $0.id == old.id }) })
            recordings = next; pendingCopy = nil; error = nil; return item.id
        } catch { if let pendingCopy { try? FileManager.default.removeItem(at: pendingCopy) }; self.error = "The recording could not be backed up. " + error.localizedDescription; return nil }
    }
    func audioURL(for id: UUID) -> URL? {
        cleanup()
        guard let item = recordings.first(where: { $0.id == id }) else { return nil }
        let url = directory.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func complete(_ id: UUID) {
        let removed = recordings.filter { $0.id == id }
        guard !removed.isEmpty else { return }
        replace(recordings.filter { $0.id != id }, removing: removed)
    }
    func deleteAll() { replace([], removing: recordings) }
    func cleanup() {
        guard !loadFailed else { return }
        let current = now()
        let removed = recordings.filter { current.timeIntervalSince($0.createdAt) >= Self.retention || !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }
        guard !removed.isEmpty else { return }
        replace(recordings.filter { item in !removed.contains(where: { $0.id == item.id }) }, removing: removed)
    }
    private func replace(_ next: [RecoverableRecording], removing: [RecoverableRecording]) {
        guard !loadFailed else { return }
        do { try writeIndex(next); removeFiles(removing); recordings = next; error = nil }
        catch { self.error = "Recovery storage could not be updated. " + error.localizedDescription }
    }
    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func writeIndex(_ entries: [RecoverableRecording]) throws {
        try prepareDirectory()
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }
    private func removeFiles(_ entries: [RecoverableRecording]) {
        for entry in entries { try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName)) }
    }
}
