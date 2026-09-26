import XCTest
@testable import Speek

@MainActor
final class DictationPipelineTests: XCTestCase {
    func testCorrectionsUseWholeWordsAndDoNotCascade() {
        let entries: [DictationVocabularyEntry] = [
            .init(term: "OpenAI", heardAs: "open eye"),
            .init(term: "Should not cascade", heardAs: "OpenAI"),
            .init(term: "C++", heardAs: "see plus plus")
        ]
        XCTAssertEqual(DictationPipeline.applyCorrections("OPEN EYE, open eyesight, see plus plus", entries: entries), "OpenAI, open eyesight, C++")
    }

    func testLongerPhraseWins() {
        let entries: [DictationVocabularyEntry] = [.init(term: "dessert", heardAs: "apple pie"), .init(term: "fruit", heardAs: "apple")]
        XCTAssertEqual(DictationPipeline.applyCorrections("apple pie and apple", entries: entries), "dessert and fruit")
    }

    func testRawNeverCallsCloudAndPolishFailurePreservesWords() async throws {
        let name = "DictationPipelineTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONEncoder().encode([DictationVocabularyEntry(term: "Speek", heardAs: "speak app")]), forKey: "speek.memory.vocabularyDrafts")
        let raw = try await DictationPipeline.process(transcript: "speak app", destination: .init(appName: "Mail"), defaults: defaults, completion: { _, _ in
            XCTFail("Raw must not call the cloud")
            return "changed"
        })
        XCTAssertEqual(raw.text, "Speek")
        defaults.set("Polished", forKey: "speek.dictation.polish")
        let fallback = try await DictationPipeline.process(transcript: "speak app", destination: .init(appName: "Mail"), defaults: defaults, completion: { _, _ in throw ActionClientError.invalidResponse })
        XCTAssertEqual(fallback.text, "Speek")
        XCTAssertNotNil(fallback.warning)
    }

    func testCancellationDoesNotBecomeFallbackSuccess() async throws {
        let name = "DictationPipelineTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("Light", forKey: "speek.dictation.polish")
        do {
            _ = try await DictationPipeline.process(transcript: "Original", destination: .init(appName: "Mail"), defaults: defaults, completion: { _, _ in throw CancellationError() })
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { }
    }
}
