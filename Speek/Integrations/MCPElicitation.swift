import Foundation
import Combine

/// A question a plugin asks while running a tool: a small form, a link to open (for example
/// to finish connecting an account), or a request to use the user's AI model. Shown in the
/// notch; one at a time.
struct MCPElicitation: Identifiable {
    struct Field: Identifiable {
        enum Kind: Equatable { case text, number(integer: Bool), toggle, choice([String], labels: [String]), multiChoice([String], labels: [String]) }
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
    /// Set for a model request: what the plugin wants to send.
    var sampling: String? = nil

    /// Separates the selected values of a multiple-choice field.
    static let separator = "\u{1F}"
}

@MainActor
final class MCPElicitationCenter: ObservableObject {
    static let shared = MCPElicitationCenter()
    @Published private(set) var current: MCPElicitation?
    /// Set by the assistant to show the card in the notch (and resize it when answered).
    var present: (() -> Void)?
    var dismissed: (() -> Void)?
    /// Runs a plugin's model request with the user's configured model: (system, input, max tokens) -> (text, model).
    nonisolated(unsafe) static var complete: ((String, String, Int) async throws -> (String, String))?
    private var continuation: CheckedContinuation<MCPValue, Never>?
    private var queue: [(MCPElicitation, CheckedContinuation<MCPValue, Never>)] = []

    /// Answers the questions a plugin asks mid-request: `elicitation/create` and
    /// `sampling/createMessage` (text only, after the user allows it). Used both for 2026
    /// `input_required` results and for server requests on earlier protocol versions.
    nonisolated static func handler(plugin: String) -> MCPServerRequestHandler {
        { method, params in
            switch method {
            case "elicitation/create":
                guard let request = parse(plugin: plugin, params) else { throw MCPError.invalidResponse }
                return await MCPElicitationCenter.shared.ask(request)
            case "sampling/createMessage":
                guard let (system, input) = samplingText(params), let complete else { throw MCPError.capabilityRequired }
                let request = MCPElicitation(plugin: plugin, message: "wants to use your AI model", fields: [], url: nil,
                                             sampling: (system.map { $0 + "\n\n" } ?? "") + input)
                guard await MCPElicitationCenter.shared.ask(request)["action"]?.string == "accept" else { throw MCPError.declined }
                let limit = params["maxTokens"].flatMap { value -> Int? in if case .number(let n) = value { return Int(n) }; return nil } ?? 1024
                let (text, model) = try await complete(system ?? "You are a helpful assistant.", input, min(max(limit, 16), 8192))
                return .object(["role": .string("assistant"), "content": .object(["type": .string("text"), "text": .string(text)]),
                                "model": .string(model), "stopReason": .string("endTurn")])
            default:
                throw MCPError.capabilityRequired
            }
        }
    }

    /// The system prompt and conversation of a model request as plain text; images and audio
    /// are noted, not sent. Tool-enabled requests are not supported (not declared).
    nonisolated static func samplingText(_ params: MCPValue) -> (system: String?, input: String)? {
        guard params["tools"] == nil, let messages = params["messages"]?.array, !messages.isEmpty else { return nil }
        func text(_ content: MCPValue?) -> String {
            let parts = content?.array ?? content.map { [$0] } ?? []
            return parts.map { part in
                switch part["type"]?.string {
                case "text": return part["text"]?.string ?? ""
                case "image": return "[image]"
                case "audio": return "[audio]"
                default: return ""
                }
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        let turns = messages.map { ($0["role"]?.string ?? "user", text($0["content"])) }
        let input = turns.count == 1 ? turns[0].1 : turns.map { ($0.0 == "assistant" ? "Assistant: " : "User: ") + $0.1 }.joined(separator: "\n\n")
        guard !input.isEmpty, input.count <= 200_000 else { return nil }
        return (params["systemPrompt"]?.string, input)
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
            case .multiChoice: content[field.id] = .array(raw.components(separatedBy: MCPElicitation.separator).filter { !$0.isEmpty }.map(MCPValue.string))
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
            // Titled options are `oneOf` (single) or `items.anyOf` (multiple) lists of const + title.
            func titled(_ list: [MCPValue]?) -> ([String], [String])? {
                let pairs = (list ?? []).compactMap { item in item["const"]?.string.map { ($0, item["title"]?.string ?? $0) } }
                return pairs.isEmpty ? nil : (pairs.map(\.0), pairs.map(\.1))
            }
            if property["type"]?.string == "array", let items = property["items"] {
                if let options = items["enum"]?.array?.compactMap(\.string), !options.isEmpty { kind = .multiChoice(options, labels: options) }
                else if let (options, labels) = titled(items["anyOf"]?.array) { kind = .multiChoice(options, labels: labels) }
                else { kind = .text }
            } else if let options = property["enum"]?.array?.compactMap(\.string), !options.isEmpty {
                kind = .choice(options, labels: property["enumNames"]?.array?.compactMap(\.string) ?? options)
            } else if let (options, labels) = titled(property["oneOf"]?.array) {
                kind = .choice(options, labels: labels)
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
            case .array(let values)?: fallback = values.compactMap(\.string).joined(separator: MCPElicitation.separator)
            default: fallback = kind == .toggle ? "false" : ""
            }
            fields.append(.init(id: key, title: title, detail: property["description"]?.string, kind: kind, required: required.contains(key), defaultValue: fallback))
        }
        return MCPElicitation(plugin: plugin, message: message, fields: fields, url: nil)
    }
}

