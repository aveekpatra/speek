import Foundation
import SwiftData
import OSLog
import CryptoKit

/// Reads the user's Claude + Codex chat logs (plain local JSONL files — the app is
/// not sandboxed) and aggregates *typed* (hand-written) words per day into
/// `TypedDailyMetric`. This feeds the gray "Napsáno" line on the Words-over-time
/// chart. It is strictly additive: it never reads or writes the dictation data
/// that drives the blue line.
///
/// Design (all decided in the feature plan):
/// - Binary split: a human chat prompt is "typed" unless its words can be matched
///   back to a dictation (`Transcription`) within 120s, in which case those words
///   are credited to dictation and subtracted.
/// - Incremental: each file is bookmarked by byte offset in `ProcessedLog`, so a
///   re-run only parses the bytes appended since last time.
/// - Streamed line-by-line; a 50MB log is never loaded whole into memory.
/// - All work runs off the main actor on a background `ModelContext`, so launch
///   and the blue line are never blocked.
enum TypedLogIngestor {

    // MARK: - Constants

    private static let logger = Logger(subsystem: "com.aveekpatra.speek", category: "TypedLogIngestor")

    /// Drop a human message whose trimmed text STARTS WITH any of these — control
    /// tags, injected hooks, resume banners, etc. (Not real typing by the user.)
    /// Kept as ONE constant array per the plan.
    private static let controlPrefixes: [String] = [
        "<command-name>",
        "<command-message>",
        "<command-args>",
        "<local-command-stdout>",
        "<local-command-caveat>",
        "<system-reminder>",
        "<task-notification>",
        "<bash-stdout>",
        "<user-prompt-submit-hook>",
        "[Request interrupted",
        "You are running an automatic",
        "This session is being continued",
        "Another Claude session sent a message:"
    ]

    /// Substrings that, if present anywhere, mark the message as injected content
    /// (a pasted recipe), not typed prose.
    private static let controlContains: [String] = [
        "## Vstupní recept",
        "# Recept:"
    ]

    /// Read window for matching a prompt back to a dictation. A dictated phrase
    /// that ends up inside a prompt typed shortly after.
    private static let dictationMatchWindow: TimeInterval = 120

    private static let lineFeed: UInt8 = 0x0A   // "\n"

    // MARK: - Log roots

    private enum LogSource {
        case claude
        case codex

        var name: String { self == .claude ? "claude" : "codex" }
    }

    /// Absolute roots of the four log trees, paired with their parser shape.
    private static func logRoots() -> [(url: URL, source: LogSource)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (home.appendingPathComponent(".claude/projects", isDirectory: true), .claude),
            (home.appendingPathComponent(".claude-ftmo/projects", isDirectory: true), .claude),
            (home.appendingPathComponent(".codex/sessions", isDirectory: true), .codex),
            (home.appendingPathComponent(".codex/archived_sessions", isDirectory: true), .codex)
        ]
    }

    // MARK: - Entry point

    /// Serializes ingest runs. The Dashboard's `.task` calls `ingestIfNeeded` on
    /// every appearance, and the work runs in a detached task that outlives the
    /// view. Without this gate, repeated appearances stack up overlapping ingests:
    /// two `ModelContext`s mutate the same SwiftData stores at once, which makes
    /// SwiftData abort (an uncatchable dynamic-cast failure) inside `save()`. The
    /// gate guarantees only ONE ingest runs at a time; a concurrent call is a no-op.
    private actor IngestGate {
        private var isRunning = false
        /// Marks running and returns true if idle; returns false if already running.
        func tryBegin() -> Bool {
            if isRunning { return false }
            isRunning = true
            return true
        }
        func end() { isRunning = false }
    }
    private static let ingestGate = IngestGate()

    /// TEMPORARILY DISABLED. This background ingest writes to SwiftData from a detached
    /// task while the main thread renders the same `Transcription` rows (Recent
    /// transcripts list). SwiftData does not tolerate that cross-thread access and
    /// intermittently aborts with an uncatchable `swift_dynamicCast` failure inside
    /// `save()`. Already-ingested data in `typed-v3.store` still renders read-only via
    /// `InsightsLoader`, so the "Napsáno" line keeps showing — it just stops updating.
    /// Re-enable only after moving ALL SwiftData access onto the main actor (heavy file
    /// parsing stays on a background task; the small DB read + write run on the main
    /// actor), or behind a dedicated `@ModelActor`.
    private static let ingestEnabled = false

    /// Ingest any new log bytes and refresh the typed aggregates. Safe to call on
    /// every launch — incremental bookmarks make repeat runs cheap. Never throws to
    /// the caller; failures are logged and swallowed so the chart still renders.
    /// Re-entrant calls while an ingest is already running are skipped (see IngestGate).
    static func ingestIfNeeded(modelContainer: ModelContainer) async {
        guard ingestEnabled else { return }
        guard await ingestGate.tryBegin() else { return }

        let task = Task.detached(priority: .utility) {
            do {
                try await runIngest(modelContainer: modelContainer)
            } catch is CancellationError {
                // Cancelled at a file boundary — partial progress is already saved.
            } catch {
                logger.error("Typed log ingest failed: \(error, privacy: .public)")
            }
        }
        await task.value
        await ingestGate.end()
    }

    // MARK: - Core

    private static func runIngest(modelContainer: ModelContainer) async throws {
        // Typed models are written through their OWN dedicated single-store container
        // (see TypedStore). Saving them through the app's shared 5-store container made
        // SwiftData abort with a dynamic-cast failure in save(). `Transcription` lives
        // in the main container, so dictations are read from there separately.
        guard let typedContainer = TypedStore.container else { return }
        let context = ModelContext(typedContainer)
        let dictationContext = ModelContext(modelContainer)

        // Same Calendar InsightsLoader uses, so day buckets line up exactly.
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")

        // One-time: the stored typed totals predate prompt-dedup. Wipe the aggregates
        // and the per-file bookmarks so this run recomputes every file from scratch
        // with duplicate prompts merged. Done once, gated by a UserDefaults flag.
        if !UserDefaults.standard.bool(forKey: dedupMigrationKey) {
            try deleteAll(TypedDailyMetric.self, context: context)
            try deleteAll(ProcessedLog.self, context: context)
            try deleteAll(TypedPromptSignature.self, context: context)
            if context.hasChanges { try context.save() }
            UserDefaults.standard.set(true, forKey: dedupMigrationKey)
        }

        // Snapshot dictations once: (timestamp, normalized text, normalized enhanced, words).
        // Read from the MAIN container — that's where Transcription is stored.
        let dictations = try loadDictationSnapshots(context: dictationContext)

        // Global dedup set: a substantial prompt whose normalized text we've already
        // counted (any file, this run or a previous one) is a repeat and is skipped.
        var seen = try loadSignatures(context: context)
        var newSignatures: [String] = []

        // Accumulate per (day, source) across all files this run, then upsert once.
        // We add deltas onto whatever is already stored for incremental files.
        var dayBuckets: [DayKey: BucketAccumulator] = [:]

        for root in logRoots() {
            let files = collectJSONLFiles(in: root.url)
            for fileURL in files {
                try Task.checkCancellation()
                let path = fileURL.path
                if path.contains("/subagents/") { continue }

                guard let processed = try processFile(
                    at: fileURL,
                    source: root.source,
                    context: context,
                    calendar: calendar,
                    dictations: dictations,
                    seen: &seen,
                    newSignatures: &newSignatures
                ) else { continue }

                for (key, value) in processed {
                    dayBuckets[key, default: BucketAccumulator()].add(value)
                }
            }
        }

        for hash in newSignatures {
            context.insert(TypedPromptSignature(hash: hash))
        }
        try upsertAggregates(dayBuckets, context: context)
        if context.hasChanges {
            try context.save()
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .typedMetricsDidChange, object: nil)
        }
    }

    // MARK: - File discovery

    /// Recursively collect every *.jsonl under `root`. Returns [] if root is absent.
    private static func collectJSONLFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            result.append(url)
        }
        return result
    }

    // MARK: - Per-file incremental parse

    /// Parse only the new bytes of one file, returning per-(day,source) deltas, or
    /// nil if there is nothing new. Updates the file's `ProcessedLog` bookmark.
    private static func processFile(
        at fileURL: URL,
        source: LogSource,
        context: ModelContext,
        calendar: Calendar,
        dictations: [DictationSnapshot],
        seen: inout Set<String>,
        newSignatures: inout [String]
    ) throws -> [DayKey: BucketAccumulator]? {
        let path = fileURL.path
        let fm = FileManager.default

        let attrs = try? fm.attributesOfItem(atPath: path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        guard fileSize > 0 else { return nil }

        let bookmark = try fetchProcessedLog(filePath: path, context: context)
        var startOffset = bookmark?.bytesProcessed ?? 0

        // File shrank (rewritten/rotated) → reparse from the top.
        if startOffset > fileSize {
            startOffset = 0
        }
        // Nothing appended since last run.
        if startOffset == fileSize {
            return nil
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(startOffset))

        var buckets: [DayKey: BucketAccumulator] = [:]

        // Stream in bounded chunks so a first-run 50MB log is never held whole in
        // memory: keep at most one chunk + one partial line buffered. Complete lines
        // are parsed and dropped; `consumedByteCount` counts only bytes up to the
        // last newline actually processed.
        var pending = Data()                 // bytes after the last newline, not yet a full line
        var consumedByteCount = 0            // bytes confirmed parsed (ending at a newline)
        let chunkSize = 1 << 20              // 1 MB

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            pending.append(chunk)

            // Parse every complete line currently buffered.
            while let newlineIndex = pending.firstIndex(of: lineFeed) {
                let lineData = pending[pending.startIndex..<newlineIndex]
                let lineLength = pending.distance(from: pending.startIndex, to: newlineIndex) + 1
                consumedByteCount += lineLength

                if !lineData.isEmpty,
                   let prompt = parsePrompt(lineData: lineData, source: source) {
                    accumulate(prompt: prompt, source: source, calendar: calendar, dictations: dictations, into: &buckets, seen: &seen, newSignatures: &newSignatures)
                }

                // Drop the consumed line (incl. its newline) from the buffer.
                pending = pending.subdata(in: pending.index(after: newlineIndex)..<pending.endIndex)
            }
        }

        // `pending` now holds a trailing partial line (no newline) — left unread
        // until it's completed on a future run. Nothing consumed → leave bookmark.
        guard consumedByteCount > 0 else { return [:] }

        // Advance the bookmark by exactly the bytes we consumed (up to last newline).
        let newOffset = startOffset + consumedByteCount
        try updateProcessedLog(
            existing: bookmark,
            filePath: path,
            source: source,
            bytesProcessed: newOffset,
            fileSize: fileSize,
            context: context
        )

        return buckets
    }

    // MARK: - Prompt extraction (Claude / Codex shapes)

    /// A surviving human prompt: its timestamp and its (paste-stripped) text.
    private struct ParsedPrompt {
        let timestamp: Date
        let text: String
    }

    private static func parsePrompt(lineData: Data, source: LogSource) -> ParsedPrompt? {
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }

        let rawText: String?
        let isoTimestamp: String?

        switch source {
        case .claude:
            rawText = claudeHumanText(from: obj)
            isoTimestamp = obj["timestamp"] as? String
        case .codex:
            rawText = codexHumanText(from: obj)
            isoTimestamp = obj["timestamp"] as? String
        }

        guard let text = rawText,
              let isoTimestamp,
              let date = parseISODate(isoTimestamp) else { return nil }

        if isControlText(text) { return nil }

        let stripped = stripPastes(from: text)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return ParsedPrompt(timestamp: date, text: stripped)
    }

    /// Claude human prompt: type=="user", not meta/sidechain, no toolUseResult, not
    /// a compact summary; message.content is a String or text-blocks (skip the whole
    /// message if any block is a tool_result).
    private static func claudeHumanText(from obj: [String: Any]) -> String? {
        guard (obj["type"] as? String) == "user" else { return nil }
        if boolValue(obj["isMeta"]) { return nil }
        if boolValue(obj["isSidechain"]) { return nil }
        if obj["toolUseResult"] != nil { return nil }
        if boolValue(obj["isCompactSummary"]) { return nil }

        guard let message = obj["message"] as? [String: Any] else { return nil }
        let content = message["content"]

        if let str = content as? String {
            return str
        }

        guard let blocks = content as? [[String: Any]] else { return nil }
        var pieces: [String] = []
        for block in blocks {
            let kind = block["type"] as? String
            if kind == "tool_result" {
                // Whole message is a tool result wrapper → not typed prose.
                return nil
            }
            if kind == "text", let t = block["text"] as? String {
                pieces.append(t)
            }
        }
        let joined = pieces.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// Codex human prompt: type=="event_msg" AND payload.type=="user_message";
    /// text = payload.message. (response_item role=="user" lines are ignored.)
    private static func codexHumanText(from obj: [String: Any]) -> String? {
        guard (obj["type"] as? String) == "event_msg" else { return nil }
        guard let payload = obj["payload"] as? [String: Any] else { return nil }
        guard (payload["type"] as? String) == "user_message" else { return nil }
        guard let message = payload["message"] as? String, !message.isEmpty else { return nil }
        return message
    }

    // MARK: - Control / injected text filter

    private static func isControlText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        for prefix in controlPrefixes where trimmed.hasPrefix(prefix) {
            return true
        }
        for needle in controlContains where trimmed.contains(needle) {
            return true
        }
        // Persona system prompts ("You are the/a/an …") that run long are injected,
        // not typed by the user.
        if matchesYouArePersona(trimmed), WordCounter.count(in: trimmed) > 200 {
            return true
        }
        return false
    }

    /// True if the text begins with "You are the/a/an " (the persona pattern).
    private static func matchesYouArePersona(_ text: String) -> Bool {
        return text.hasPrefix("You are the ")
            || text.hasPrefix("You are a ")
            || text.hasPrefix("You are an ")
    }

    // MARK: - Internal paste-strip (tightened; NOT a visible category)

    /// Remove obvious pasted material so a stray code block / URL / hash doesn't
    /// inflate the typed count. Tightened per plan: fenced code blocks, whole-line
    /// URLs, long hex tokens. No base64-by-length, no \b word boundaries.
    private static func stripPastes(from text: String) -> String {
        var working = removeFencedCodeBlocks(text)
        working = removeStandaloneURLs(working)
        working = removeLongHexTokens(working)
        return working
    }

    /// Drop everything between triple-backtick fences (and the fences themselves).
    private static func removeFencedCodeBlocks(_ text: String) -> String {
        let fence = "```"
        guard text.contains(fence) else { return text }
        let segments = text.components(separatedBy: fence)
        // Even-indexed segments are outside fences; odd-indexed are inside.
        var kept: [String] = []
        for (index, segment) in segments.enumerated() where index % 2 == 0 {
            kept.append(segment)
        }
        return kept.joined(separator: " ")
    }

    /// Remove a line ONLY if the entire trimmed line is a single URL.
    private static func removeStandaloneURLs(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !isStandaloneURL(trimmed)
        }
        return filtered.joined(separator: "\n")
    }

    private static func isStandaloneURL(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        // ^https?://\S+$ — the whole line is the URL, no inner whitespace.
        return !trimmed.contains(where: { $0 == " " || $0 == "\t" })
    }

    /// Remove standalone hex tokens of length >= 40 (commit SHAs, hashes). Splits on
    /// whitespace; no \b word boundaries.
    private static func removeLongHexTokens(_ text: String) -> String {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        let kept = tokens.filter { token in
            !isLongHexToken(token)
        }
        return kept.joined(separator: " ")
    }

    private static func isLongHexToken(_ token: Substring) -> Bool {
        guard token.count >= 40 else { return false }
        for ch in token where !ch.isHexDigit {
            return false
        }
        return true
    }

    // MARK: - Bucketing + dictation subtraction

    private struct DayKey: Hashable {
        let day: Date
        let source: String
    }

    /// Running totals for one (day, source) bucket while a run is in progress.
    private struct BucketAccumulator {
        var rawWords: Int = 0
        var dictationSubtracted: Int = 0

        mutating func add(_ other: BucketAccumulator) {
            rawWords += other.rawWords
            dictationSubtracted += other.dictationSubtracted
        }

        /// Net typed words, clamped >= 0.
        var netTypedWords: Int { max(rawWords - dictationSubtracted, 0) }
    }

    private static func accumulate(
        prompt: ParsedPrompt,
        source: LogSource,
        calendar: Calendar,
        dictations: [DictationSnapshot],
        into buckets: inout [DayKey: BucketAccumulator],
        seen: inout Set<String>,
        newSignatures: inout [String]
    ) {
        let gross = WordCounter.count(in: prompt.text)
        guard gross > 0 else { return }

        // Merge repeated prompts: a substantial prompt whose normalized text we've
        // already counted is a repeat (re-sent, or the same message re-appearing in
        // another log file after a resume/compact) — skip it. Short prompts (<= 10
        // words: "yes", "ok", "continue") are never deduped so normal chatter counts.
        if gross > 10 {
            let sig = signature(for: prompt.text)
            if seen.contains(sig) { return }
            seen.insert(sig)
            newSignatures.append(sig)
        }

        let subtracted = dictationCredit(for: prompt, dictations: dictations)

        let day = calendar.startOfDay(for: prompt.timestamp)
        let key = DayKey(day: day, source: source.name)
        buckets[key, default: BucketAccumulator()].add(
            BucketAccumulator(rawWords: gross, dictationSubtracted: subtracted)
        )
    }

    /// If a dictation finished within `dictationMatchWindow` BEFORE this prompt and
    /// its (normalized) text is a substring of the prompt, those words belong to
    /// dictation, not typing. Matching is cross-file (we hold all dictations).
    private static func dictationCredit(for prompt: ParsedPrompt, dictations: [DictationSnapshot]) -> Int {
        let promptNorm = normalize(prompt.text)
        guard !promptNorm.isEmpty else { return 0 }

        let windowStart = prompt.timestamp.addingTimeInterval(-dictationMatchWindow)
        var credit = 0
        for dictation in dictations {
            // Dictation must precede the prompt and be within 120s of it.
            guard dictation.timestamp <= prompt.timestamp,
                  dictation.timestamp >= windowStart else { continue }

            if !dictation.normalizedText.isEmpty, promptNorm.contains(dictation.normalizedText) {
                credit += dictation.wordCount
                continue
            }
            if !dictation.normalizedEnhanced.isEmpty, promptNorm.contains(dictation.normalizedEnhanced) {
                credit += dictation.wordCount
            }
        }
        return credit
    }

    // MARK: - Dictation snapshot (read-only)

    /// A frozen view of one `Transcription` for substring matching.
    private struct DictationSnapshot {
        let timestamp: Date
        let normalizedText: String
        let normalizedEnhanced: String
        let wordCount: Int
    }

    private static func loadDictationSnapshots(context: ModelContext) throws -> [DictationSnapshot] {
        let descriptor = FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\.timestamp)])
        let rows = try context.fetch(descriptor)
        return rows.compactMap { row in
            let normText = normalize(row.text)
            let normEnhanced = normalize(row.enhancedText ?? "")
            if normText.isEmpty && normEnhanced.isEmpty { return nil }
            // Credit the dictated word count from whichever variant we matched on; use
            // the enhanced text's count when present, else the raw text's, mirroring
            // how the dictation pipeline counts.
            let wordSource = !normEnhanced.isEmpty ? (row.enhancedText ?? "") : row.text
            return DictationSnapshot(
                timestamp: row.timestamp,
                normalizedText: normText,
                normalizedEnhanced: normEnhanced,
                wordCount: WordCounter.count(in: wordSource)
            )
        }
    }

    /// Lowercased, whitespace-collapsed form for substring matching.
    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let collapsed = lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt dedup (hash only, never the text)

    /// Flag for the one-time recompute that wipes pre-dedup totals + bookmarks.
    private static let dedupMigrationKey = "typedDedupMigrationV1Done"

    /// SHA-256 hex of the normalized prompt — a fingerprint that can't be reversed
    /// back to what was typed. Two prompts with identical normalized text share it.
    private static func signature(for text: String) -> String {
        let digest = SHA256.hash(data: Data(normalize(text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Load every stored prompt fingerprint into a set for fast repeat lookups.
    private static func loadSignatures(context: ModelContext) throws -> Set<String> {
        let rows = try context.fetch(FetchDescriptor<TypedPromptSignature>())
        return Set(rows.map(\.hash))
    }

    /// Delete every row of a model in the typed store (used by the one-time reset).
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<T>())
        for row in rows { context.delete(row) }
    }

    // MARK: - Upsert aggregates

    private static func upsertAggregates(
        _ buckets: [DayKey: BucketAccumulator],
        context: ModelContext
    ) throws {
        for (key, accumulator) in buckets {
            let day = key.day
            let source = key.source
            var descriptor = FetchDescriptor<TypedDailyMetric>(
                predicate: #Predicate { $0.day == day && $0.source == source }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor).first

            if let metric = existing {
                // Incremental: add this run's deltas onto the stored totals.
                metric.rawWords += accumulator.rawWords
                metric.dictationSubtracted += accumulator.dictationSubtracted
                metric.typedWords = max(metric.rawWords - metric.dictationSubtracted, 0)
                metric.computedAt = Date()
            } else {
                let metric = TypedDailyMetric(
                    day: day,
                    source: source,
                    typedWords: accumulator.netTypedWords,
                    rawWords: accumulator.rawWords,
                    dictationSubtracted: accumulator.dictationSubtracted
                )
                context.insert(metric)
            }
        }
    }

    // MARK: - ProcessedLog bookmark (upsert by unique filePath)

    private static func fetchProcessedLog(filePath: String, context: ModelContext) throws -> ProcessedLog? {
        var descriptor = FetchDescriptor<ProcessedLog>(
            predicate: #Predicate { $0.filePath == filePath }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func updateProcessedLog(
        existing: ProcessedLog?,
        filePath: String,
        source: LogSource,
        bytesProcessed: Int,
        fileSize: Int,
        context: ModelContext
    ) throws {
        if let log = existing {
            log.bytesProcessed = bytesProcessed
            log.fileSize = fileSize
            log.source = source.name
            log.lastParsedAt = Date()
        } else {
            let log = ProcessedLog(
                filePath: filePath,
                source: source.name,
                bytesProcessed: bytesProcessed,
                fileSize: fileSize
            )
            context.insert(log)
        }
    }

    // MARK: - Timestamp parsing

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parse a UTC (Z) ISO8601 timestamp; handles both with and without fractional
    /// seconds (Claude uses .665Z millis; Codex uses .168Z millis; some lack them).
    private static func parseISODate(_ iso: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: iso) {
            return date
        }
        return isoFormatter.date(from: iso)
    }

    // MARK: - JSON bool helper

    /// A truthy JSON boolean. Treats true/1 as true; missing/false/0/other as false.
    private static func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }
}
