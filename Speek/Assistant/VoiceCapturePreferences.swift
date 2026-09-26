import Foundation

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
    static func language(defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: "speek.voice.recognitionLanguage") ?? ""
        return !value.isEmpty && languages.contains(where: { $0.id == value }) ? value : nil
    }
    static func keywords(defaults: UserDefaults = .standard) -> [String] {
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
        return result
    }
    // Verified against OpenAI's file transcription guide. New-model arrays use repeated multipart fields.
    static func openAIFields(model: String, defaults: UserDefaults = .standard) -> [(String, String)] {
        var fields: [(String, String)] = []
        if let language = language(defaults: defaults) { fields.append((model == "gpt-transcribe" ? "languages[]" : "language", language)) }
        let terms = keywords(defaults: defaults)
        if model == "gpt-transcribe" { fields.append(contentsOf: terms.map { ("keywords[]", $0) }) }
        else if model == "gpt-4o-transcribe" || model == "gpt-4o-mini-transcribe" {
            let prompt = String(terms.joined(separator: ", ").prefix(400))
            if !prompt.isEmpty { fields.append(("prompt", prompt)) }
        }
        return fields
    }
}
