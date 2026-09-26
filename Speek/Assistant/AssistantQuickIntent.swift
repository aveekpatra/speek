import Foundation

/// Exact, low-risk commands can run without a model round trip.
enum AssistantQuickIntent {
    static func action(for input: String) -> ProposedAction? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.hasPrefix("remember that ") {
            let fact = String(text.dropFirst("remember that ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fact.isEmpty else { return nil }
            return ProposedAction(kind: .remember, title: "Remember", target: fact, response: "")
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
}
