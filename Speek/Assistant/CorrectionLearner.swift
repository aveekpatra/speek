import AppKit
import ApplicationServices

/// After a dictation is inserted, watches the field for two minutes. When the user fixes a word
/// or short phrase inside what was dictated (a misheard name, a casing fix), Speek saves it to
/// Memory > Vocabulary so the next dictation gets it right, and shows it briefly under the notch
/// with Undo. Other edits (rewording, grammar, text typed after) are ignored.
@MainActor
final class CorrectionLearner: ObservableObject {
    static let shared = CorrectionLearner()
    static let enabledKey = "speek.dictation.learnCorrections"

    /// The most recently learned entry, for Undo.
    @Published private(set) var lastLearned: DictationVocabularyEntry?
    /// Set for a few seconds after learning, for the notch notice.
    @Published private(set) var notice: DictationVocabularyEntry?
    private var watcher: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    func watch(target: VoiceTarget, inserted: String) {
        stopWatching()
        let dictated = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isEnabled, target.localTextView == nil, dictated.count >= 2 else { return }
        watcher = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let snapshot = Self.value(of: target), snapshot.contains(dictated) else { return }
            var latest = snapshot
            var evaluated = snapshot
            var stableSince = Date()
            var learnedHeard = Set<String>()
            let deadline = Date().addingTimeInterval(120)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(1000))
                let focused = target.isStillFocused()
                guard let current = Self.value(of: target) else { return }
                if current != latest { latest = current; stableSince = Date() }
                // Evaluate whenever edits settle, and once more when the user moves on.
                if current != evaluated, !focused || Date().timeIntervalSince(stableSince) >= 2.5 {
                    evaluated = current
                    for pair in Self.learnedPairs(before: snapshot, after: current, inserted: dictated)
                    where learnedHeard.insert(pair.heard.lowercased()).inserted {
                        self?.learn(pair)
                    }
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
        dismissNotice()
    }

    func dismissNotice() { noticeTask?.cancel(); notice = nil }

    private func learn(_ pair: LearnedPair) {
        var entries = DictationPipeline.vocabulary()
        // A fix the user makes replaces a learned rule for the same sound.
        if let index = entries.firstIndex(where: { !$0.heardAs.isEmpty && $0.heardAs.caseInsensitiveCompare(pair.heard) == .orderedSame }) {
            guard entries[index].learned == true, entries[index].term != pair.term else { return }
            entries.remove(at: index)
        }
        let heard = pair.replaces ? pair.heard : ""
        guard pair.replaces || !entries.contains(where: { $0.term == pair.term }) else { return }
        let entry = DictationVocabularyEntry(term: pair.term, heardAs: heard, learned: true)
        entries.append(entry)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: "speek.memory.vocabularyDrafts")
        lastLearned = entry
        notice = entry
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private static func value(of target: VoiceTarget) -> String? {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(target.element, 0.15)
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= 2_000_000 else { return nil }
        return text
    }

    struct LearnedPair: Equatable {
        let heard: String
        let term: String
        /// True: always replace `heard` with `term`. False: `heard` is made of ordinary words
        /// ("a week" for "Aveek"), so the term is only a transcription hint.
        let replaces: Bool
    }

    /// The first learnable fix, if any (kept for callers that expect one).
    nonisolated static func learnedPair(before: String, after: String, inserted: String) -> (heard: String, term: String)? {
        learnedPairs(before: before, after: after, inserted: inserted).first.map { ($0.heard, $0.term) }
    }

    /// Word-level fixes between two versions of a field that fall inside the dictated text:
    /// replaced runs of at most four words, similar in spelling (or a casing change of a name).
    /// Text added or removed elsewhere, and rewording, are ignored.
    nonisolated static func learnedPairs(before: String, after: String, inserted: String) -> [LearnedPair] {
        let old = before as NSString, new = after as NSString
        let insertion = old.range(of: inserted, options: .backwards)
        guard insertion.location != NSNotFound, old != new else { return [] }
        // Trim what both versions share so only the edited region is compared word by word.
        var prefix = 0
        while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        func isWord(_ c: unichar) -> Bool { CharacterSet.alphanumerics.contains(UnicodeScalar(c) ?? " ") || c == 39 || c == 0x2019 }
        while prefix > 0, isWord(old.character(at: prefix - 1)) { prefix -= 1 }
        while suffix > 0, isWord(old.character(at: old.length - suffix)) { suffix -= 1 }
        let oldWords = words(in: old, range: NSRange(location: prefix, length: old.length - prefix - suffix))
        let newWords = words(in: new, range: NSRange(location: prefix, length: new.length - prefix - suffix))
        guard oldWords.count <= 400, newWords.count <= 400 else { return [] }
        // Longest common subsequence of words; a gap with words on both sides is a replacement.
        let a = oldWords.map(\.text), b = newWords.map(\.text)
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [LearnedPair] = []
        var i = 0, j = 0
        var removed: [Word] = [], added: [Word] = []
        func flush() {
            defer { removed = []; added = [] }
            guard !removed.isEmpty, !added.isEmpty,
                  removed.first!.range.location >= insertion.location, NSMaxRange(removed.last!.range) <= NSMaxRange(insertion),
                  let pair = classify(heard: removed.map(\.text).joined(separator: " "), term: added.map(\.text).joined(separator: " ")) else { return }
            pairs.append(pair)
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] { flush(); i += 1; j += 1 }
            else if j < b.count, i == a.count || table[i][j + 1] >= table[i + 1][j] { added.append(newWords[j]); j += 1 }
            else { removed.append(oldWords[i]); i += 1 }
        }
        flush()
        return pairs
    }

    private struct Word { let text: String; let range: NSRange }

    /// Whitespace-separated words with surrounding punctuation removed ("C++" and "C#" keep theirs).
    nonisolated private static func words(in text: NSString, range: NSRange) -> [Word] {
        var result: [Word] = []
        let trim = CharacterSet.punctuationCharacters.union(.symbols).subtracting(CharacterSet(charactersIn: "+#"))
        let chunk = text.substring(with: range) as NSString
        let regex = try! NSRegularExpression(pattern: "\\S+")
        for match in regex.matches(in: chunk as String, range: NSRange(location: 0, length: chunk.length)) {
            let raw = chunk.substring(with: match.range)
            let leading = raw.prefix { $0.unicodeScalars.allSatisfy(trim.contains) }.utf16.count
            let core = raw.trimmingCharacters(in: trim)
            guard !core.isEmpty else { continue }
            result.append(Word(text: core, range: NSRange(location: range.location + match.range.location + leading, length: core.utf16.count)))
        }
        return result
    }

    /// Whether a replacement looks like a recognition fix, and how to save it.
    nonisolated static func classify(heard: String, term: String) -> LearnedPair? {
        guard heard != term, heard.count <= 40, term.count <= 40,
              heard.split(separator: " ").count <= 4, term.split(separator: " ").count <= 4,
              term.contains(where: \.isLetter) else { return nil }
        let heardWords = heard.lowercased().split(separator: " ").map(String.init)
        let ordinary = heardWords.allSatisfy(isDictionaryWord)
        if heard.caseInsensitiveCompare(term) == .orderedSame {
            // "iphone" to "iPhone" is a name; "hello" to "Hello" is just a sentence start.
            let shaped = term.dropFirst().contains(where: \.isUppercase) || (term.count >= 2 && term.filter(\.isLetter).allSatisfy(\.isUppercase))
            guard !ordinary || shaped else { return nil }
            return LearnedPair(heard: heard, term: term, replaces: true)
        }
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
        guard Double(row[b.count]) / Double(max(a.count, b.count)) <= 0.5 else { return nil }
        // Swapping one ordinary word for another ("their" to "there") is grammar, not vocabulary.
        let termOrdinary = term.lowercased().split(separator: " ").allSatisfy { isDictionaryWord(String($0)) }
        if ordinary && termOrdinary && term.first?.isUppercase != true { return nil }
        // Ordinary words are only a hint unless the phrase is long enough to be distinctive.
        return LearnedPair(heard: heard, term: term, replaces: !ordinary || heardWords.count >= 3)
    }

    nonisolated private static func isDictionaryWord(_ word: String) -> Bool {
        guard word.count > 1 else { return true }
        let check = { NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound }
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }
}
