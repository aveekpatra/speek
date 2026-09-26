import Foundation
@main struct Checks {
    @MainActor static func main() async throws {
        let catalog = NativeOrganizerTools.catalog
        assert(catalog.count == 11)
        assert(Set(catalog.map(\.name)).count == 11)
        for tool in catalog {
            let schema = try JSONSerialization.jsonObject(with: Data(tool.inputSchemaJSON.utf8)) as! [String: Any]
            assert(schema["type"] as? String == "object")
            assert(schema["additionalProperties"] as? Bool == false)
            assert(schema["properties"] is [String: Any])
        }
        for tool in catalog where tool.requiresConfirmation {
            do {
                _ = try await NativeOrganizerTools.shared.execute(name: tool.name, argumentsJSON: "{}")
                assertionFailure("Mutation executed without approval")
            } catch { assert(error.localizedDescription.contains("approve")) }
        }
        print("PASS: 11 valid schemas, unique names, all mutation approval gates")
    }
}
