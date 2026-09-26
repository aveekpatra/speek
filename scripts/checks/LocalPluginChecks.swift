import Foundation

@main struct LocalPluginChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("speek-local-plugin-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = CommandLine.arguments[1]
        let schema = MCPValue.object(["type": .string("object"), "properties": .object(["value": .object(["type": .string("string")])])])
        let manifest = LocalPluginManifest(schemaVersion: 1, name: "Fixture", description: "Offline fixture", executable: "/usr/bin/python3", tools: [
            .init(name: "echo", description: "Echo input", inputSchema: schema, arguments: [fixture, "echo", "{{value}}"], timeoutSeconds: 3),
            .init(name: "wait", description: "Wait", inputSchema: schema, arguments: [fixture, "wait"], timeoutSeconds: 1),
            .init(name: "large", description: "Oversized response", inputSchema: schema, arguments: [fixture, "large"], timeoutSeconds: 3),
            .init(name: "fail", description: "Failure", inputSchema: schema, arguments: [fixture, "fail"], timeoutSeconds: 3)
        ], dictationHook: .init(arguments: [fixture, "hook"], timeoutSeconds: 3))
        let store = LocalPluginStore(directory: directory)
        try store.install(manifest)
        let id = store.plugins[0].id
        precondition(store.availableTools.isEmpty && !store.plugins[0].hookEnabled)
        try store.setEnabled(id: id, enabled: true)
        let tools = store.availableTools
        precondition(tools.count == 4)
        let literal = "hello; $(touch " + directory.appendingPathComponent("should-not-exist").path + ")"
        let result = try await store.execute(toolID: tools[0].id, arguments: ["value": .string(literal)])
        precondition(result.structuredContent?["arguments"]?.array?.first?.string == literal)
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("should-not-exist").path))
        let before = await store.processDictation(text: "hello", appBundleID: "com.test.app")
        precondition(before.text == "hello")
        do { try store.setHookEnabled(id: id, enabled: true); fatalError("Hook enabled without app grant") } catch {}
        try store.addHookApplication(pluginID: id, bundleID: "com.test.app", name: "Test")
        try store.setHookEnabled(id: id, enabled: true)
        let after = await store.processDictation(text: "hello", appBundleID: "com.test.app")
        precondition(after.text == "HELLO" && after.warnings.isEmpty)
        let other = await store.processDictation(text: "hello", appBundleID: "com.other.app")
        precondition(other.text == "hello")
        try store.removeHookApplication(pluginID: id, bundleID: "com.test.app")
        precondition(!store.plugins[0].hookEnabled)
        for name in ["wait", "large", "fail"] {
            do { _ = try await store.execute(toolID: tools.first { $0.name == name }!.id, arguments: [:]); fatalError("Expected failure for " + name) }
            catch {}
        }
        let cancelled = Task { try await store.execute(toolID: tools[1].id, arguments: [:]) }
        try await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        var broken = manifest
        broken.name = "Broken hook"
        broken.tools = []
        broken.dictationHook = .init(arguments: [fixture, "invalid-hook"], timeoutSeconds: 3)
        try store.install(broken)
        let brokenID = store.plugins[1].id
        try store.setEnabled(id: brokenID, enabled: true)
        try store.addHookApplication(pluginID: brokenID, bundleID: "com.test.app", name: "Test")
        try store.setHookEnabled(id: brokenID, enabled: true)
        let recovered = await store.processDictation(text: "original", appBundleID: "com.test.app")
        precondition(recovered.text == "original" && recovered.warnings.count == 1)
        let reload = LocalPluginStore(directory: directory)
        precondition(reload.plugins.count == 2)
        try store.setEnabled(id: id, enabled: false)
        precondition(store.availableTools.isEmpty)
        print("PASS: explicit enable/app grants, literal argv, JSON stdin/output, hook isolation/recovery, timeout, output cap, cancellation, persistence")
    }
}
