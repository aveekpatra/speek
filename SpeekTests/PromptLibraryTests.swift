import XCTest
@testable import Speek

@MainActor
final class PromptLibraryTests: XCTestCase {
    func testVariablesAndSinglePassSubstitution() throws {
        XCTAssertEqual(PromptTemplate.variables(in: "{{ name }} {{topic}} {{name}}"), ["name", "topic"])
        XCTAssertEqual(try PromptTemplate.render("{{name}}: {{topic}}", values: ["name": "{{topic}}", "topic": "$value"]), "{{topic}}: $value")
        XCTAssertThrowsError(try PromptTemplate.render("{{missing}}", values: [:]))
    }

    func testPersistenceEditingFavoritesAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("prompts.json")
        let library = PromptLibrary(file: file)
        XCTAssertTrue(library.save(name: "Research", body: "Research {{topic}}"))
        let id = try XCTUnwrap(library.prompts.first?.id)
        library.toggleFavorite(id)
        XCTAssertTrue(library.save(id: id, name: "Explain", body: "Explain {{topic}}"))
        let restored = PromptLibrary(file: file)
        XCTAssertEqual(restored.prompts.first?.name, "Explain")
        XCTAssertEqual(restored.prompts.first?.isFavorite, true)
        restored.remove(id)
        XCTAssertTrue(PromptLibrary(file: file).prompts.isEmpty)
    }
}
