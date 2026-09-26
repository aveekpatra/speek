import XCTest
@testable import Speek

@MainActor
final class DictationHistoryTests: XCTestCase {
    func testPrivacyRetentionAndInsights() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let suite = "DictationHistoryTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = DictationHistory(file: file, defaults: defaults)
        defaults.set(false, forKey: "speek.assistant.saveHistory")
        history.record(text: "Do not save", duration: 2, appName: "Mail")
        XCTAssertTrue(history.entries.isEmpty)
        defaults.set(true, forKey: "speek.assistant.saveHistory")
        history.record(text: "one two three four", duration: 2, appName: "Mail")
        XCTAssertEqual(history.insights.words, 4)
        XCTAssertEqual(history.insights.estimatedSecondsSaved, 4)
        for index in 0..<501 { history.record(text: "Item \(index)", duration: -1, appName: "Mail") }
        XCTAssertEqual(history.entries.count, 500)
        XCTAssertEqual(history.entries.first?.text, "Item 1")
        XCTAssertTrue(history.entries.allSatisfy { $0.duration >= 0 })
        XCTAssertEqual(DictationHistory(file: file, defaults: defaults).entries.count, 500)
        history.clear()
        XCTAssertTrue(DictationHistory(file: file, defaults: defaults).entries.isEmpty)
    }
}
