import Foundation
import SwiftData

/// Per-file bookmark for incremental parsing of a chat log (Claude/Codex JSONL).
/// Stored in its own `typed.store` (additive). Lets us resume from `bytesProcessed`
/// on the next run instead of re-reading whole 50MB files.
@Model
final class ProcessedLog {
    /// Absolute file path — looked up manually so one row is maintained per log file.
    var filePath: String = ""
    var id: UUID = UUID()
    /// Which chat log this is: "claude" or "codex".
    var source: String = "claude"
    /// How many bytes from the start of the file we have already parsed.
    var bytesProcessed: Int = 0
    /// File size at the time of the last parse (used to detect growth/truncation).
    var fileSize: Int = 0
    var lastParsedAt: Date = Date()

    init(
        filePath: String,
        source: String,
        bytesProcessed: Int,
        fileSize: Int,
        lastParsedAt: Date = Date()
    ) {
        self.id = UUID()
        self.filePath = filePath
        self.source = source
        self.bytesProcessed = bytesProcessed
        self.fileSize = fileSize
        self.lastParsedAt = lastParsedAt
    }
}
