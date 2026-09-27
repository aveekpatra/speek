import Foundation

enum CodexJobError: LocalizedError {
    case notInstalled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Install the Codex CLI on this Mac to use this feature."
        case .failed(let message): return message
        }
    }
}
