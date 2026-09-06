import Foundation
import SwiftData

/// One typed-prompt fingerprint: the SHA-256 hex of the lowercased, whitespace-
/// collapsed prompt text. Used to merge repeated typed prompts so the same prompt —
/// sent again, or re-appearing in another log file after a resume/compact — is
/// counted only once on the "Napsáno" line.
///
/// Stores ONLY the hash, never the prompt text. A hash cannot be reversed back to
/// what was typed.
@Model
final class TypedPromptSignature {
    var hash: String
    var firstSeenAt: Date = Date()

    init(hash: String, firstSeenAt: Date = Date()) {
        self.hash = hash
        self.firstSeenAt = firstSeenAt
    }
}
