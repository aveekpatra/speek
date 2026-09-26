import XCTest
@testable import Speek

@MainActor
final class AssistantMemoryTests: XCTestCase {
    func testLegacyMigrationPersistenceAndPrivacy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("memory.json")
        let suite = "AssistantMemoryTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try JSONEncoder().encode([RememberedFact(text: "Keep replies concise")]).write(to: file)
        let memory = AssistantMemory(file: file, defaults: defaults)
        XCTAssertEqual(memory.facts.count, 1)
        memory.saveProcedure(title: "Weekly update", instructions: "Summarize project progress in three bullets.")
        memory.recordEpisode(request: "Weekly project update", result: "Report saved.")
        memory.recordEpisode(request: "Weekly project update", result: "Report saved.")
        let restored = AssistantMemory(file: file, defaults: defaults)
        XCTAssertEqual(restored.facts.count, 1)
        XCTAssertEqual(restored.procedures.count, 1)
        XCTAssertEqual(restored.episodes.count, 1)
        XCTAssertTrue(restored.context(for: "weekly project").contains("Report saved."))
        XCTAssertFalse(restored.context(for: "recipe baking").contains("Report saved."))
        restored.saveHistory = false
        restored.recordEpisode(request: "Private request", result: "Private result")
        XCTAssertEqual(restored.episodes.count, 1)
        XCTAssertFalse(restored.context(for: "weekly project").contains("Report saved."))
    }

    func testCorruptMemoryIsNeverOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = Data("invalid existing memory".utf8)
        try bytes.write(to: file)
        let memory = AssistantMemory(file: file)
        memory.remember("New fact")
        XCTAssertNotNil(memory.persistenceError)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
