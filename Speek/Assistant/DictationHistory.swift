import Foundation
import Combine

struct DictationHistoryEntry: Codable, Identifiable {
    var id = UUID()
    var text: String
    var duration: TimeInterval
    var appName: String
    var date = Date()
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

struct DictationInsights {
    var sessions: Int
    var words: Int
    var audioSeconds: TimeInterval
    /// A transparent estimate, not a measured productivity result.
    var estimatedSecondsSaved: TimeInterval { max(0, Double(words) / 40 * 60 - audioSeconds) }
}

@MainActor
final class DictationHistory: ObservableObject {
    static let shared = DictationHistory()
    @Published private(set) var entries: [DictationHistoryEntry] = []
    @Published private(set) var error: String?
    private let file: URL
    private let defaults: UserDefaults
    private var loadFailed = false
    static let retentionLimit = 500

    init(file: URL? = nil, defaults: UserDefaults = .standard) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek/dictation-history.json")
        self.defaults = defaults
        guard FileManager.default.fileExists(atPath: self.file.path) else { return }
        do { entries = Array(try JSONDecoder().decode([DictationHistoryEntry].self, from: Data(contentsOf: self.file)).suffix(Self.retentionLimit)) }
        catch { loadFailed = true; self.error = "Dictation history could not be loaded. The existing file has been preserved." }
    }
    var insights: DictationInsights {
        DictationInsights(sessions: entries.count, words: entries.reduce(0) { $0 + $1.wordCount }, audioSeconds: entries.reduce(0) { $0 + max(0, $1.duration) })
    }
    func record(text: String, duration: TimeInterval, appName: String) {
        guard defaults.object(forKey: "speek.assistant.saveHistory") as? Bool ?? true else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let duration = duration.isFinite ? min(max(0, duration), 7200) : 0
        let entry = DictationHistoryEntry(text: String(clean.prefix(100_000)), duration: duration, appName: String(appName.prefix(200)))
        _ = persist(Array((entries + [entry]).suffix(Self.retentionLimit)))
    }
    func remove(_ id: UUID) { _ = persist(entries.filter { $0.id != id }) }
    func clear() { _ = persist([]) }
    func export(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func persist(_ next: [DictationHistoryEntry]) -> Bool {
        guard !loadFailed else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            entries = next; error = nil; return true
        } catch { self.error = "Dictation history could not be saved. " + error.localizedDescription; return false }
    }
}
