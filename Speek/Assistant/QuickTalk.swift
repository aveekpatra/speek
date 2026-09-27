import Foundation

/// The fast first step of every request: a small, quick model call that either answers directly
/// (conversation, questions, quick help) or recognizes a task and says a short acknowledgment
/// before the agent starts. This is what makes Speek feel like talking to someone.
enum QuickTalk {
    struct Decision: Equatable {
        /// True: `text` is the whole answer. False: `text` is what to say before doing the task.
        let reply: Bool
        let text: String
    }

    static let system = """
    You are Speek, a friendly, quick voice assistant on the user's Mac. Decide how to handle the request.
    Reply directly (mode "reply") when it can be answered from general knowledge, the conversation, or the saved facts: chat, questions, explanations, math, advice, word help, a short text to say or write. Keep replies natural and brief for speaking: one to three sentences unless the user asks for more. No markdown, no lists, no emoji.
    Treat it as a task (mode "task") when it needs anything on the Mac or online: apps, email, messages, calendar, reminders, notes, files, music, settings, the web, current information (news, weather, prices, scores), the screen, saving something to memory or the dictation vocabulary, or anything that changes something. Then "text" is a short, natural acknowledgment of what you are about to do, at most 12 words, like "Sure, adding that to Thursday." or "Checking your inbox now." Never say it is already done.
    Answer with JSON only: {"mode":"reply" or "task","text":"..."}.
    """

    /// Nil when the model is unreachable or answers something unusable; the agent then handles the request.
    static func decide(_ request: String, history: [ActionMessage], facts: [String], app: String?,
                       complete: @escaping (String, String) async throws -> String) async -> Decision? {
        let recent = history.suffix(6).map { ($0.role == .user ? "User: " : "Speek: ") + String($0.text.prefix(400)) }.joined(separator: "\n")
        let input = """
        Time: \(Date().formatted(date: .complete, time: .shortened)). Front app: \(app ?? "unknown").
        Saved facts about the user: \(facts.isEmpty ? "none" : facts.prefix(20).joined(separator: "; "))
        Conversation so far:
        \(recent.isEmpty ? "(none)" : recent)
        Request: \(request)
        """
        let output: String
        do {
            output = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await complete(system, input) }
                group.addTask { try await Task.sleep(for: .seconds(6)); throw CancellationError() }
                defer { group.cancelAll() }
                return try await group.next() ?? ""
            }
        } catch { return nil }
        return parse(output)
    }

    static func parse(_ output: String) -> Decision? {
        guard let object = RuntimeCall.firstObject(in: output), let mode = object["mode"]?.string,
              let text = object["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        switch mode {
        case "reply": return Decision(reply: true, text: text)
        case "task": return Decision(reply: false, text: text)
        default: return nil
        }
    }

    /// Requests about what is on screen go straight to the agent, which can see it.
    static func refersToScreen(_ text: String) -> Bool {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: ["this", "these", "here", "screen", "above", "below", "selected", "circled", "highlighted"])
    }

    /// What to say out loud: short answers whole, long ones by their first sentences.
    static func forSpeech(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: "[*_`#>]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard plain.count > 320 else { return plain }
        var spoken = ""
        plain.enumerateSubstrings(in: plain.startIndex..., options: .bySentences) { sentence, _, _, stop in
            guard let sentence else { return }
            if spoken.count + sentence.count > 260 { stop = true; return }
            spoken += sentence
        }
        return (spoken.isEmpty ? String(plain.prefix(240)) : spoken).trimmingCharacters(in: .whitespaces) + " The rest is in the notch."
    }

    /// The question asked out loud when an action needs the user's OK.
    static func approvalLine(for call: RuntimeCall?, title: String) -> String {
        if let call, let card = RichCard.detect(call) {
            switch card {
            case .message(let message):
                let who = message.to.flatMap { $0.split(separator: ",").first.map { " to " + $0.trimmingCharacters(in: .whitespaces) } } ?? ""
                return message.sends ? "I wrote the message\(who). Should I send it?" : "I drafted it\(who). Want me to save the draft?"
            case .event(let event): return "Ready to add \(event.title.isEmpty ? "the event" : event.title). Should I save it?"
            case .file: return "Ready to change that file. Should I go ahead?"
            case .music: return "Want me to play it?"
            }
        }
        return "I need your OK to \(title.prefix(1).lowercased() + title.dropFirst()). Should I go ahead?"
    }

    /// Spoken answers to an approval question.
    static let yes: Set<String> = ["yes", "yeah", "yep", "sure", "ok", "okay", "do it", "go ahead", "run it", "send it", "save it", "play it",
                                   "yes please", "please do", "confirm", "sounds good", "go for it"]
    static let no: Set<String> = ["no", "nope", "cancel", "never mind", "nevermind", "don't", "dont", "stop", "no thanks"]
}
