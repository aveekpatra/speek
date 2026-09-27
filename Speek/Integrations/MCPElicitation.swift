import Foundation
import Combine

/// A question a plugin asks while running a tool: a small form, or a link to open
/// (for example to finish connecting an account). Shown in the notch; one at a time.
struct MCPElicitation: Identifiable {
    struct Field: Identifiable {
        enum Kind: Equatable { case text, number(integer: Bool), toggle, choice([String], labels: [String]) }
        let id: String
        let title: String
        let detail: String?
        let kind: Kind
        let required: Bool
        let defaultValue: String
    }
    let id = UUID()
    let plugin: String
    let message: String
    let fields: [Field]
    let url: URL?
}

@MainActor
final class MCPElicitationCenter: ObservableObject {
    static let shared = MCPElicitationCenter()
    @Published private(set) var current: MCPElicitation?
    /// Set by the assistant to show the card in the notch (and resize it when answered).
    var present: (() -> Void)?
    var dismissed: (() -> Void)?
    private var continuation: CheckedContinuation<MCPValue, Never>?
    private var queue: [(MCPElicitation, CheckedContinuation<MCPValue, Never>)] = []

    /// Called by transports for `elicitation/create`. Other server requests are not supported.
    nonisolated static func handler(plugin: String) -> MCPServerRequestHandler {
        { method, params in
            guard method == "elicitation/create" else { throw MCPError.capabilityRequired }
            guard let request = parse(plugin: plugin, params) else { throw MCPError.invalidResponse }
            return await MCPElicitationCenter.shared.ask(request)
        }
    }

    func ask(_ request: MCPElicitation) async -> MCPValue {
        await withCheckedContinuation { continuation in
            if current == nil {
                current = request; self.continuation = continuation
                present?()
            } else {
                queue.append((request, continuation))
            }
        }
    }

    func submit(_ values: [String: String]) {
        guard let request = current else { return }
        var content: [String: MCPValue] = [:]
        for field in request.fields {
            let raw = (values[field.id] ?? field.defaultValue).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            switch field.kind {
            case .toggle: content[field.id] = .bool(raw == "true")
            case .number: if let number = Double(raw) { content[field.id] = .number(number) }
            default: content[field.id] = .string(raw)
            }
        }
        finish(.object(["action": .string("accept"), "content": .object(content)]))
    }

    func decline() { finish(.object(["action": .string("decline")])) }
    func cancel() { finish(.object(["action": .string("cancel")])) }

    private func finish(_ result: MCPValue) {
        let pending = continuation
        continuation = nil; current = nil
        pending?.resume(returning: result)
        if !queue.isEmpty {
            let (next, nextContinuation) = queue.removeFirst()
            current = next; continuation = nextContinuation
            present?()
        } else {
            dismissed?()
        }
    }

    nonisolated static func parse(plugin: String, _ params: MCPValue) -> MCPElicitation? {
        let message = params["message"]?.string ?? "The plugin needs more information."
        if params["mode"]?.string == "url" {
            guard let text = params["url"]?.string, let url = URL(string: text), url.scheme == "https" else { return nil }
            return MCPElicitation(plugin: plugin, message: message, fields: [], url: url)
        }
        let schema = params["requestedSchema"]
        let required = Set(schema?["required"]?.array?.compactMap(\.string) ?? [])
        var fields: [MCPElicitation.Field] = []
        for (key, property) in (schema?["properties"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            let title = property["title"]?.string ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            let kind: MCPElicitation.Field.Kind
            if let options = property["enum"]?.array?.compactMap(\.string), !options.isEmpty {
                kind = .choice(options, labels: property["enumNames"]?.array?.compactMap(\.string) ?? options)
            } else {
                switch property["type"]?.string {
                case "boolean": kind = .toggle
                case "number": kind = .number(integer: false)
                case "integer": kind = .number(integer: true)
                default: kind = .text
                }
            }
            let fallback: String
            switch property["default"] {
            case .string(let value)?: fallback = value
            case .bool(let value)?: fallback = value ? "true" : "false"
            case .number(let value)?: fallback = value.rounded() == value ? String(Int(value)) : String(value)
            default: fallback = kind == .toggle ? "false" : ""
            }
            fields.append(.init(id: key, title: title, detail: property["description"]?.string, kind: kind, required: required.contains(key), defaultValue: fallback))
        }
        return MCPElicitation(plugin: plugin, message: message, fields: fields, url: nil)
    }
}

