import Foundation
import AppKit

struct ActionIntegration: Identifiable {
    let id: ProposedActionKind
    let name: String
    let detail: String
    let symbol: String

    static let catalog: [ActionIntegration] = [
        ActionIntegration(id: .openWebsite, name: "Open website", detail: "Public HTTPS pages", symbol: "safari"),
        ActionIntegration(id: .searchWeb, name: "Web search", detail: "Browser search results", symbol: "magnifyingglass")
    ]
}

@MainActor
enum ActionExecutor {
    static func run(_ action: ProposedAction, threadID: UUID, projectFolder: String, image: Data? = nil) async throws -> String {
        switch action.kind {
        case .openApp:
            let name = action.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("/"), !name.contains("..") else {
                throw ActionClientError.requestFailed("That application name is not valid.")
            }
            let appName = name.hasSuffix(".app") ? name : name + ".app"
            let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
            guard let app = roots.map({ URL(fileURLWithPath: $0).appendingPathComponent(appName) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw ActionClientError.requestFailed("I could not find \(name) in Applications.")
            }
            try await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            return "Opened \(name)."
        case .remember:
            return AssistantMemory.shared.remember(action.target) ? "Remembered: \(action.target)" : "Already remembered: \(action.target)"
        case .openWebsite:
            guard let url = safeWebsiteURL(action.target) else {
                throw ActionClientError.requestFailed("This website address is not allowed.")
            }
            guard NSWorkspace.shared.open(url) else {
                throw ActionClientError.requestFailed("macOS could not open this website.")
            }
            return "Opened \(url.host ?? "website")."
        case .searchWeb:
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: action.target)]
            guard let url = components.url else { throw ActionClientError.invalidResponse }
            guard NSWorkspace.shared.open(url) else {
                throw ActionClientError.requestFailed("macOS could not open the search results.")
            }
            return "Opened web results for \(action.target)."
        case .toolCall:
            throw ActionClientError.requestFailed("This action must run through the reviewed tool workflow.")
        case .answer, .unsupported:
            return action.response
        }
    }

    nonisolated static func safeWebsiteURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed) else { return nil }
        if parts.scheme == nil { parts = URLComponents(string: "https://\(trimmed)") ?? parts }
        guard parts.scheme == "https", let host = parts.host?.lowercased(),
              host.contains("."), host.rangeOfCharacter(from: .letters) != nil,
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
              parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        return parts.url
    }
}
