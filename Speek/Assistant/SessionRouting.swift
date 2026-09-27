import Foundation

/// When a notch request continues the current conversation. A voice assistant has no "new chat"
/// button in the moment, so the boundary is decided from time and wording.
enum SessionRouting {
    /// Under 10 minutes since the last turn continues; so does under an hour when the request
    /// refers back to it ("it", "that", "send it").
    static func continues(idle: TimeInterval, refersBack: Bool) -> Bool {
        idle < 600 || (refersBack && idle < 3600)
    }

    static func refersBack(_ text: String) -> Bool {
        let words = Set(text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init))
        let references: Set<String> = ["it", "it's", "that", "those", "these", "them", "him", "her", "again", "instead", "also", "too",
                                       "same", "other", "another", "more", "yes", "no", "undo", "previous", "last", "one", "there"]
        return !words.isDisjoint(with: references)
    }
}
