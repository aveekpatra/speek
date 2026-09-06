import Foundation
import SwiftData

/// Suggests candidate vocabulary words mined from the user's recent transcriptions,
/// so they can be added to the custom vocabulary with one click.
enum VocabularySuggestionService {
    private static let dismissedDefaultsKey = "dismissedVocabularySuggestions"
    private static let recentTranscriptionLimit = 200
    private static let minWordLength = 4
    private static let minDistinctTranscriptions = 3
    private static let maxSuggestions = 10

    struct Suggestion: Identifiable {
        var id: String { word }
        let word: String
    }

    // MARK: - Suggestions

    static func suggestions(context: ModelContext, existing: [VocabularyWord]) -> [Suggestion] {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = recentTranscriptionLimit

        guard let transcriptions = try? context.fetch(descriptor), !transcriptions.isEmpty else {
            return []
        }

        let existingWords = Set(existing.map { $0.word.lowercased() })
        let dismissedWords = Set(dismissedSuggestions().map { $0.lowercased() })

        // For each candidate word (lowercased key), track: distinct transcription count
        // and whether it was ever seen capitalized mid-sentence (likely proper noun/term).
        var distinctCounts: [String: Int] = [:]
        var displayWords: [String: String] = [:]
        var seenCapitalizedMidSentence: Set<String> = []

        for transcription in transcriptions {
            let text = transcription.enhancedText ?? transcription.text
            guard !text.isEmpty else { continue }

            let tokens = tokenize(text)
            var seenInThisTranscription: Set<String> = []

            for (index, token) in tokens.enumerated() {
                guard token.count >= minWordLength else { continue }
                let lower = token.lowercased()
                guard !stopwords.contains(lower) else { continue }
                guard token.rangeOfCharacter(from: .letters) != nil else { continue }

                if seenInThisTranscription.insert(lower).inserted {
                    distinctCounts[lower, default: 0] += 1
                }

                if displayWords[lower] == nil {
                    displayWords[lower] = token
                }

                // Mid-sentence = not the first token, and starts with an uppercase letter
                // while not being fully uppercase (avoid acronym over-weighting, still fine either way).
                if index > 0, let first = token.first, first.isUppercase {
                    seenCapitalizedMidSentence.insert(lower)
                }
            }
        }

        let candidates = distinctCounts
            .filter { lower, count in
                count >= minDistinctTranscriptions
                    && !existingWords.contains(lower)
                    && !dismissedWords.contains(lower)
            }
            .sorted { lhs, rhs in
                let lhsCapitalized = seenCapitalizedMidSentence.contains(lhs.key)
                let rhsCapitalized = seenCapitalizedMidSentence.contains(rhs.key)
                if lhsCapitalized != rhsCapitalized {
                    return lhsCapitalized && !rhsCapitalized
                }
                return lhs.value > rhs.value
            }
            .prefix(maxSuggestions)

        return candidates.compactMap { lower, _ in
            displayWords[lower].map { Suggestion(word: $0) }
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Dismissal

    static func dismissedSuggestions() -> [String] {
        UserDefaults.standard.stringArray(forKey: dismissedDefaultsKey) ?? []
    }

    static func isDismissed(_ word: String) -> Bool {
        dismissedSuggestions().contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    static func dismiss(_ word: String) {
        var dismissed = dismissedSuggestions()
        guard !dismissed.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        dismissed.append(word)
        UserDefaults.standard.set(dismissed, forKey: dismissedDefaultsKey)
    }

    // MARK: - Stopwords (English + Czech function words, kept lowercase)

    private static let stopwords: Set<String> = [
        // English articles, pronouns, prepositions, conjunctions, auxiliaries
        "the", "and", "for", "are", "was", "were", "been", "being", "have", "has", "had",
        "this", "that", "these", "those", "with", "from", "into", "onto", "upon", "over",
        "under", "about", "above", "below", "between", "among", "through", "during",
        "before", "after", "again", "further", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "any", "both", "each", "few", "more", "most",
        "other", "some", "such", "only", "same", "than", "too", "very", "just", "should",
        "would", "could", "will", "shall", "can", "does", "did", "doing", "done",
        "you", "your", "yours", "yourself", "yourselves", "he", "him", "his", "himself",
        "she", "her", "hers", "herself", "it", "its", "itself", "they", "them", "their",
        "theirs", "themselves", "who", "whom", "whose", "what", "which", "whichever",
        "not", "nor", "but", "because", "while", "against", "off", "out", "down", "up",
        "also", "like", "even", "still", "yet", "much", "many", "well", "back", "away",
        "really", "actually", "basically", "maybe", "perhaps", "probably", "sure",
        "okay", "yeah", "yes", "know", "think", "want", "need", "make", "made", "going",
        "get", "got", "getting", "let", "lets", "right", "left", "good", "bad", "great",
        "little", "big", "small", "long", "short", "high", "low", "next", "last", "first",
        "second", "third", "always", "never", "sometimes", "often", "usually", "today",
        "tomorrow", "yesterday", "now", "soon", "later", "already",
        "myself", "ourselves", "our", "ours", "wasn", "isn", "aren", "wasnt",
        "arent", "isnt", "dont", "doesnt", "didnt", "cant", "couldnt", "wouldnt",
        "shouldnt", "wont", "hasnt", "havent", "hadnt", "thats", "whats", "youre",
        "theyre", "ive", "youve", "weve", "theyve", "im",
        "something", "anything", "everything", "nothing", "someone", "anyone",
        "everyone", "somewhere", "anywhere", "everywhere", "kind", "sort", "thing",
        "things", "way", "ways", "lot", "lots", "bit", "part", "parts",
        // Czech function words, pronouns, prepositions, conjunctions, common verbs
        "a", "aby", "ale", "ani", "ano", "asi", "až", "být", "byl", "byla",
        "bylo", "byli", "bych", "bys", "byste", "bychom", "co", "což",
        "dnes", "do", "ho", "i", "já", "jak", "jako", "jde", "je", "jeho", "jej",
        "její", "jejich", "jen", "ještě", "jestli", "jestliže", "jí", "jich", "jím",
        "jimi", "jinak", "již", "jsem", "jsi", "jsme", "jsou", "jste", "k", "kam",
        "každý", "kde", "kdo", "kdy", "když", "ke", "kolik", "kromě", "která",
        "které", "který", "kteří", "mají", "máte", "mě", "mezi",
        "mi", "mít", "mne", "mnou", "moc", "mohl", "moje", "moji", "možná",
        "musí", "my", "na", "nad", "nám", "námi", "naše", "naši", "ne",
        "nebo", "nebyl", "nechť", "něco", "nedělá", "někde", "někdo", "nemají",
        "nemáte", "nemusí", "než", "nic", "nich", "ním", "nimi", "od",
        "odkud", "ode", "on", "ona", "oni", "ono", "ony", "pak", "patří",
        "před", "přede", "přes", "při", "po", "pod", "podle", "pokud", "potom",
        "pouze", "právě", "pro", "proč", "proto", "protože", "první",
        "s", "se", "si", "sice", "smí", "snad", "spolu",
        "svá", "svým", "svými", "ta", "tady", "tak", "takhle", "taky", "takže",
        "tam", "tamhle", "tato", "tě", "tedy", "tento", "ti", "tím",
        "tímto", "to", "tobě", "toho", "tohle", "toto", "tu",
        "tuto", "tvá", "tvé", "tvoje", "ty", "u", "určitě", "už", "vám",
        "vámi", "vás", "vaše", "vaši", "ve", "více", "však", "všechen",
        "všechno", "všichni", "vy", "z", "za", "zatímco", "ze", "že",
    ]
}
