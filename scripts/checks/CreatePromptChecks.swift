import Foundation

enum ActionConnection { case openRouter, localCodex; static var preferred: Self { .localCodex } }
enum ActionClientError: Error { case invalidResponse; case requestFailed(String) }
struct ActionMessage {}
struct ProposedAction { enum Kind { case answer, toolCall }; let kind: Kind; let response: String }
final class OpenRouterActionClient {
    static let shared = OpenRouterActionClient()
    func propose(_ text: String, history: [ActionMessage], contextNotes: String?, images: [Data], modelID: String?, reasoningEffort: String?) async throws -> ProposedAction { throw ActionClientError.invalidResponse }
}
enum CodexConnection {
    static func propose(_ text: String, history: [ActionMessage], notes: String?, connection: ActionConnection, images: [Data], modelID: String?, reasoningEffort: String?) async throws -> ProposedAction { throw ActionClientError.invalidResponse }
}
@main struct Checks {
    @MainActor static func main() async throws {
        let image = Data([1, 2, 3])
        let session = CreatePromptSession(initialText: "Make a page", contextText: "Source", images: [image], refiner: { draft, revision, images in
            precondition(draft.contains("[Image 1]")); precondition(revision == "Concise"); precondition(images == [image])
            return "Refined prompt [Image 1]"
        })
        let original = session.text
        session.revision = "Concise"; session.refine()
        while session.isRefining { await Task.yield() }
        precondition(session.text == "Refined prompt [Image 1]" && session.images == [image])
        session.restorePrevious(); precondition(session.text == original)
        let failure = CreatePromptSession(initialText: "Keep me", contextText: "", images: [], refiner: { _, _, _ in throw ActionClientError.invalidResponse })
        failure.refine(); while failure.isRefining { await Task.yield() }
        precondition(failure.text == "Keep me" && failure.error != nil)
        let cancelled = CreatePromptSession(initialText: "Original", contextText: "", images: [], refiner: { _, _, _ in
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "Late result"
        })
        cancelled.refine(); await Task.yield(); cancelled.cancelRefinement()
        try await Task.sleep(nanoseconds: 70_000_000)
        precondition(cancelled.text == "Original" && !cancelled.isRefining)
        let capped = CreatePromptSession(initialText: "", contextText: String(repeating: "x", count: 25_000), images: [], refiner: { _, _, _ in "" })
        precondition(capped.contextWasShortened && capped.text.contains("[Context excerpt ends here.]"))
        print("Create Prompt checks passed: composition, numbered images, refine, undo, failure preservation, cancellation, context cap.")
    }
}
