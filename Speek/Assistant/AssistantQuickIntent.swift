import Foundation

/// Exact, low-risk commands can run without a model round trip.
enum AssistantQuickIntent {
    /// "Remember ..." saves a fact; "forget ..." removes the saved fact that best matches.
    /// "Remember to ..." is a reminder, not a fact, and questions go to the model.
    static let rememberPrefixes = ["remember that ", "don't forget that ", "do not forget that ", "note that ", "keep in mind that ",
                                   "keep in mind ", "don't forget ", "do not forget ", "remember "]
    static let forgetPrefixes = ["forget that ", "forget about ", "forget "]

    @MainActor
    static func action(for input: String) async -> ProposedAction? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if let fact = remainder(of: text, after: rememberPrefixes), !lower.hasPrefix("remember to "), !lower.hasPrefix("remember when "),
           !text.hasSuffix("?") {
            return ProposedAction(kind: .remember, title: "Remember", target: fact, response: "")
        }
        if let target = remainder(of: text, after: forgetPrefixes), !["it", "that", "this", "everything"].contains(target.lowercased()),
           !text.hasSuffix("?") {
            guard let fact = await AssistantMemory.shared.bestFact(matching: target) else {
                return ProposedAction(kind: .answer, title: "Nothing to forget", target: "", response: "I don't have anything saved about that.")
            }
            let call = RuntimeCall(tool: "memory.forget", arguments: ["id": .string(fact.id.uuidString)])
            return ProposedAction(kind: .toolCall, title: "Forget: " + fact.text, target: call.json, response: "")
        }
        guard lower.hasPrefix("open ") else { return nil }
        let target = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        let knownApps = ["safari": "Safari", "calendar": "Calendar", "notes": "Notes", "reminders": "Reminders", "calculator": "Calculator", "terminal": "Terminal", "system settings": "System Settings", "codex": "Codex"]
        if let name = knownApps[target.lowercased()] {
            return ProposedAction(kind: .openApp, title: "Open " + name, target: name, response: "")
        }
        if target.hasPrefix("https://"), !target.contains(where: \.isWhitespace) {
            return ProposedAction(kind: .openWebsite, title: "Open website", target: target, response: "")
        }
        return nil
    }

    /// The text after the first matching prefix (case-insensitive), without trailing punctuation.
    static func remainder(of text: String, after prefixes: [String]) -> String? {
        let lower = text.lowercased()
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let rest = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!")))
        return rest.isEmpty ? nil : rest
    }
}
