import Foundation
import Combine

struct SavedPrompt: Codable, Identifiable {
    var id = UUID()
    var name: String
    var body: String
    var isFavorite = false
    var updatedAt = Date()

    var variables: [String] { PromptTemplate.variables(in: body) }
}

enum PromptTemplateError: LocalizedError {
    case missingVariable(String)
    case invalidPrompt
    case unreadableLibrary
    var errorDescription: String? {
        switch self {
        case .missingVariable(let name): return "Enter a value for " + name + "."
        case .invalidPrompt: return "Enter a name and prompt before saving."
        case .unreadableLibrary: return "The saved prompt library could not be read. Its file has been preserved."
        }
    }
}

enum PromptTemplate {
    private static let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9_ -]{0,63}?)\s*\}\}"#
    static func variables(in body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = body as NSString
        var names: [String] = []
        for match in regex.matches(in: body, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
    /// Substitution happens once, so values containing braces never become new instructions to the renderer.
    static func render(_ body: String, values: [String: String]) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        let source = body as NSString
        let rendered = NSMutableString(string: body)
        for match in regex.matches(in: body, range: NSRange(location: 0, length: source.length)).reversed() {
            let name = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard let value = values[name], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PromptTemplateError.missingVariable(name) }
            rendered.replaceCharacters(in: match.range, with: value)
        }
        return rendered as String
    }
}

@MainActor
final class PromptLibrary: ObservableObject {
    static let shared = PromptLibrary()
    @Published private(set) var prompts: [SavedPrompt] = []
    @Published private(set) var error: String?
    private let file: URL
    private var loadFailed = false

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek/prompts.json")
        guard FileManager.default.fileExists(atPath: self.file.path) else { return }
        do { prompts = try JSONDecoder().decode([SavedPrompt].self, from: Data(contentsOf: self.file)) }
        catch { loadFailed = true; self.error = PromptTemplateError.unreadableLibrary.localizedDescription }
    }

    @discardableResult func save(id: UUID? = nil, name: String, body: String) -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let body = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32000))
        guard !name.isEmpty, !body.isEmpty else { error = PromptTemplateError.invalidPrompt.localizedDescription; return false }
        var next = prompts
        if let id, let index = next.firstIndex(where: { $0.id == id }) {
            next[index].name = name; next[index].body = body; next[index].updatedAt = Date()
        } else { next.append(SavedPrompt(name: name, body: body)) }
        return persist(next)
    }
    func remove(_ id: UUID) { _ = persist(prompts.filter { $0.id != id }) }
    func toggleFavorite(_ id: UUID) {
        var next = prompts
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].isFavorite.toggle()
        _ = persist(next)
    }
    private func persist(_ next: [SavedPrompt]) -> Bool {
        guard !loadFailed else { error = PromptTemplateError.unreadableLibrary.localizedDescription; return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            prompts = next; error = nil; return true
        } catch { self.error = "The prompt could not be saved. " + error.localizedDescription; return false }
    }
}
