import Foundation
import SwiftData

/// One language-coaching correction surfaced after an English dictation.
/// Stored in its own `coach.store` (additive — never touches existing data).
@Model
final class CoachNote {
    var id: UUID = UUID()
    /// Soft link to the dictation it came from (cross-store, so a plain UUID — not a @Relationship).
    var dictationId: UUID = UUID()
    var timestamp: Date = Date()
    /// The phrase the user actually said (the minimal differing part).
    var said: String = ""
    /// The more natural version.
    var corrected: String = ""
    /// A short, plain-language reason it's more natural.
    var why: String = ""
    /// BCP-47-ish language tag of the dictation (e.g. "en").
    var language: String = "en"

    init(
        dictationId: UUID,
        said: String,
        corrected: String,
        why: String,
        language: String = "en",
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.dictationId = dictationId
        self.said = said
        self.corrected = corrected
        self.why = why
        self.language = language
        self.timestamp = timestamp
    }
}
