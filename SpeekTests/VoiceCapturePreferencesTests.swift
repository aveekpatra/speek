import XCTest
@testable import Speek

final class VoiceCapturePreferencesTests: XCTestCase {
    func testProviderFieldsAndSafeVocabulary() throws {
        let suite = "VoiceCapturePreferencesTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(VoiceCapturePreferences.language(defaults: defaults))
        defaults.set("invalid", forKey: "speek.voice.recognitionLanguage")
        XCTAssertNil(VoiceCapturePreferences.language(defaults: defaults))
        defaults.set("cs", forKey: "speek.voice.recognitionLanguage")
        defaults.set(try JSONEncoder().encode([DictationVocabularyEntry(term: "Speek", heardAs: "speak"), .init(term: "bad\nterm", heardAs: ""), .init(term: "<bad>", heardAs: ""), .init(term: "Speek", heardAs: "")]), forKey: "speek.memory.vocabularyDrafts")
        XCTAssertEqual(VoiceCapturePreferences.keywords(defaults: defaults), ["Speek"])
        XCTAssertEqual(VoiceCapturePreferences.openAIFields(model: "gpt-transcribe", defaults: defaults).map { $0.0 }, ["languages[]", "keywords[]"])
        XCTAssertEqual(VoiceCapturePreferences.openAIFields(model: "gpt-4o-transcribe", defaults: defaults).map { $0.0 }, ["language", "prompt"])
        defaults.set(false, forKey: "speek.voice.vocabularyHints")
        XCTAssertTrue(VoiceCapturePreferences.keywords(defaults: defaults).isEmpty)
    }
}
