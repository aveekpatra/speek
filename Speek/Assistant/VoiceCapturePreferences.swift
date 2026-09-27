import Foundation
import NaturalLanguage

struct RecognitionLanguage: Identifiable {
    var id: String
    var name: String
}

enum VoiceCapturePreferences {
    static let languages: [RecognitionLanguage] = [
        .init(id: "", name: "Automatic"), .init(id: "en", name: "English"),
        .init(id: "ar", name: "Arabic"), .init(id: "bn", name: "Bengali"),
        .init(id: "zh", name: "Chinese"), .init(id: "cs", name: "Czech"),
        .init(id: "da", name: "Danish"), .init(id: "nl", name: "Dutch"),
        .init(id: "fi", name: "Finnish"), .init(id: "fr", name: "French"),
        .init(id: "de", name: "German"), .init(id: "el", name: "Greek"),
        .init(id: "he", name: "Hebrew"), .init(id: "hi", name: "Hindi"),
        .init(id: "hu", name: "Hungarian"), .init(id: "id", name: "Indonesian"),
        .init(id: "it", name: "Italian"), .init(id: "ja", name: "Japanese"),
        .init(id: "ko", name: "Korean"), .init(id: "ms", name: "Malay"),
        .init(id: "no", name: "Norwegian"), .init(id: "pl", name: "Polish"),
        .init(id: "pt", name: "Portuguese"), .init(id: "ro", name: "Romanian"),
        .init(id: "ru", name: "Russian"), .init(id: "sk", name: "Slovak"),
        .init(id: "es", name: "Spanish"), .init(id: "sv", name: "Swedish"),
        .init(id: "ta", name: "Tamil"), .init(id: "te", name: "Telugu"),
        .init(id: "th", name: "Thai"), .init(id: "tr", name: "Turkish"),
        .init(id: "uk", name: "Ukrainian"), .init(id: "vi", name: "Vietnamese")
    ]
    static let languagesKey = "speek.voice.languages"

    /// The languages the user speaks, primary first. Empty means any language.
    /// Migrates the earlier single-language setting on first read.
    static func enabledLanguages(defaults: UserDefaults = .standard) -> [String] {
        if let saved = defaults.stringArray(forKey: languagesKey) {
            return saved.filter { id in !id.isEmpty && languages.contains { $0.id == id } }
        }
        let legacy = defaults.string(forKey: "speek.voice.recognitionLanguage") ?? ""
        return !legacy.isEmpty && languages.contains(where: { $0.id == legacy }) ? [legacy] : []
    }

    static func setEnabledLanguages(_ ids: [String], defaults: UserDefaults = .standard) {
        defaults.set(ids, forKey: languagesKey)
    }

    /// A single language to force; nil when the user speaks several or any language.
    static func language(defaults: UserDefaults = .standard) -> String? {
        let enabled = enabledLanguages(defaults: defaults)
        return enabled.count == 1 ? enabled[0] : nil
    }

    static func name(for id: String) -> String { languages.first { $0.id == id }?.name ?? id }

    /// When the transcript is clearly in a language the user does not speak (auto-detection
    /// misfired), returns the enabled language to retry with. Uses on-device text detection.
    static func retryLanguage(for transcript: String, enabled: [String]) -> String? {
        guard enabled.count >= 2, transcript.count >= 8 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(transcript)
        let detected = recognizer.languageHypotheses(withMaximum: 3)
        guard let (top, confidence) = detected.max(by: { $0.value < $1.value }), confidence >= 0.6 else { return nil }
        let code = String(top.rawValue.prefix(2))
        guard !enabled.contains(code) else { return nil }
        recognizer.reset()
        recognizer.languageConstraints = enabled.map { NLLanguage(rawValue: $0) }
        recognizer.processString(transcript)
        return recognizer.dominantLanguage.map { String($0.rawValue.prefix(2)) }.flatMap { enabled.contains($0) ? $0 : nil } ?? enabled[0]
    }
    /// Terms from around the cursor for the dictation in progress.
    nonisolated(unsafe) static var contextTerms: [String] = []

    static func keywords(defaults: UserDefaults = .standard) -> [String] {
        let context = contextTerms
        guard defaults.object(forKey: "speek.voice.vocabularyHints") as? Bool ?? true,
              let data = defaults.data(forKey: "speek.memory.vocabularyDrafts"),
              let entries = try? JSONDecoder().decode([DictationVocabularyEntry].self, from: data) else { return [] }
        var result: [String] = []
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= 80,
                  !term.contains(where: { $0 == "<" || $0 == ">" || $0 == "\n" || $0 == "\r" }),
                  !result.contains(term) else { continue }
            result.append(term)
            if result.count == 30 { break }
        }
        for term in context where result.count < 40 && !result.contains(term) { result.append(term) }
        return result
    }
    // Verified against OpenAI's file transcription guide. New-model arrays use repeated multipart fields.
    static func openAIFields(model: String, forcing forced: String? = nil, defaults: UserDefaults = .standard) -> [(String, String)] {
        var fields: [(String, String)] = []
        if let forced {
            fields.append((model == "gpt-transcribe" ? "languages[]" : "language", forced))
        } else if model == "gpt-transcribe" {
            // The newer model accepts every language the user speaks.
            fields.append(contentsOf: enabledLanguages(defaults: defaults).map { ("languages[]", $0) })
        } else if let language = language(defaults: defaults) {
            fields.append(("language", language))
        }
        let terms = keywords(defaults: defaults)
        if model == "gpt-transcribe" { fields.append(contentsOf: terms.map { ("keywords[]", $0) }) }
        else if model == "gpt-4o-transcribe" || model == "gpt-4o-mini-transcribe" {
            let prompt = String(terms.joined(separator: ", ").prefix(400))
            if !prompt.isEmpty { fields.append(("prompt", prompt)) }
        }
        return fields
    }
}
