import AppKit
import ApplicationServices

/// After a dictation is inserted, watches the field briefly. When the user fixes a word or
/// short phrase inside what was dictated (a misheard name, a casing fix), Speek saves it to
/// Memory > Vocabulary so the next dictation gets it right. Undo removes the last one.
@MainActor
final class CorrectionLearner: ObservableObject {
    static let shared = CorrectionLearner()
    static let enabledKey = "speek.dictation.learnCorrections"

    /// The most recently learned entry, for Undo.
    @Published private(set) var lastLearned: DictationVocabularyEntry?
    private var watcher: Task<Void, Never>?

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    func watch(target: VoiceTarget, inserted: String) {
        stopWatching()
        guard Self.isEnabled, target.localTextView == nil, inserted.count >= 2 else { return }
        watcher = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let snapshot = Self.value(of: target), snapshot.contains(inserted) else { return }
            var latest = snapshot
            var stableSince = Date()
            let deadline = Date().addingTimeInterval(90)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(1500))
                let focused = target.isStillFocused()
                guard let current = Self.value(of: target) else { return }
                if current != latest { latest = current; stableSince = Date() }
                // Evaluate once edits settle, or right away when the user moves on.
                if current != snapshot, !focused || Date().timeIntervalSince(stableSince) >= 3 {
                    if let pair = Self.learnedPair(before: snapshot, after: current, inserted: inserted) { self?.learn(pair) }
                    return
                }
                if !focused { return }
            }
        }
    }

    func stopWatching() { watcher?.cancel(); watcher = nil }

    func undoLast() {
        guard let entry = lastLearned else { return }
        var entries = DictationPipeline.vocabulary()
        entries.removeAll { $0.id == entry.id }
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: "speek.memory.vocabularyDrafts")
        lastLearned = nil
    }

    private func learn(_ pair: (heard: String, term: String)) {
        var entries = DictationPipeline.vocabulary()
        guard !entries.contains(where: { $0.heardAs.caseInsensitiveCompare(pair.heard) == .orderedSame }) else { return }
        let entry = DictationVocabularyEntry(term: pair.term, heardAs: pair.heard, learned: true)
        entries.append(entry)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: "speek.memory.vocabularyDrafts")
        lastLearned = entry
    }

    private static func value(of target: VoiceTarget) -> String? {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(target.element, 0.15)
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= 2_000_000 else { return nil }
        return text
    }

    /// The word-level change between two versions of a field, if it is a small fix inside the
    /// dictated text: at most four words, similar in spelling (or a casing change).
    nonisolated static func learnedPair(before: String, after: String, inserted: String) -> (heard: String, term: String)? {
        let old = before as NSString, new = after as NSString
        let insertion = old.range(of: inserted, options: .backwards)
        guard insertion.location != NSNotFound, old != new else { return nil }
        var prefix = 0
        while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        // Widen to whole words; the widened characters are shared by both versions.
        func isWord(_ c: unichar) -> Bool { CharacterSet.alphanumerics.contains(UnicodeScalar(c) ?? " ") || c == 39 }
        while prefix > 0, isWord(old.character(at: prefix - 1)) { prefix -= 1 }
        while suffix > 0, isWord(old.character(at: old.length - suffix)) { suffix -= 1 }
        let removedRange = NSRange(location: prefix, length: old.length - prefix - suffix)
        let addedRange = NSRange(location: prefix, length: new.length - prefix - suffix)
        guard removedRange.length > 0, addedRange.length > 0,
              removedRange.location >= insertion.location, NSMaxRange(removedRange) <= NSMaxRange(insertion) else { return nil }
        let heard = old.substring(with: removedRange).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let term = new.substring(with: addedRange).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !heard.isEmpty, !term.isEmpty, heard != term, heard.count <= 40, term.count <= 40,
              heard.split(separator: " ").count <= 4, term.split(separator: " ").count <= 4,
              term.contains(where: \.isLetter), !term.contains("\n") else { return nil }
        if heard.caseInsensitiveCompare(term) == .orderedSame { return (heard, term) }
        // Recognition errors sound alike and usually spell alike; a different word is an edit, not a fix.
        let a = Array(heard.lowercased().filter(\.isLetter)), b = Array(term.lowercased().filter(\.isLetter))
        guard !a.isEmpty, !b.isEmpty else { return nil }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        let distance = Double(row[b.count]) / Double(max(a.count, b.count))
        return distance <= 0.5 ? (heard, term) : nil
    }
}
