import Foundation
import SwiftData

/// One day's typed-words aggregate for a single source (Claude or Codex).
/// Stored in its own `typed.store` (additive — never touches existing dictation data).
/// Feeds the gray "Napsáno" line on the Words-over-time chart.
@Model
final class TypedDailyMetric {
    var id: UUID = UUID()
    /// Start-of-day (system timezone) bucket this aggregate belongs to.
    var day: Date = Date()
    /// Which chat log this came from: "claude" or "codex".
    var source: String = "claude"
    /// Net typed words for the day after dictation subtraction (clamped >= 0).
    var typedWords: Int = 0
    /// Gross typed words before dictation subtraction.
    var rawWords: Int = 0
    /// Words credited to dictation and subtracted out of the gross.
    var dictationSubtracted: Int = 0
    /// When this aggregate was last (re)computed.
    var computedAt: Date = Date()

    init(
        day: Date,
        source: String,
        typedWords: Int,
        rawWords: Int,
        dictationSubtracted: Int,
        computedAt: Date = Date()
    ) {
        self.id = UUID()
        self.day = day
        self.source = source
        self.typedWords = typedWords
        self.rawWords = rawWords
        self.dictationSubtracted = dictationSubtracted
        self.computedAt = computedAt
    }
}
