import Foundation

enum CodexJobError: LocalizedError {
    case notInstalled
    case invalidDirectory
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Install the Codex CLI to run coding tasks."
        case .invalidDirectory: return "Choose an existing project folder before running Codex."
        case .failed(let message): return message
        }
    }
}

@MainActor
final class CodexJobRunner {
    static let shared = CodexJobRunner()
    static var isInstalled: Bool {
        CodexConnection.binary != nil
    }
    private init() {}

    func run(prompt: String, directory: String, sessionID: String?, connection: ActionConnection = .localCodex, image: Data? = nil, modelID: String? = nil, reasoningEffort: String? = nil) async throws -> (message: String, sessionID: String?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexJobError.invalidDirectory
        }
        guard let binary = CodexConnection.binary else {
            throw CodexJobError.notInstalled
        }

        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("speek-codex-\(UUID().uuidString).jsonl")
        let finalURL = FileManager.default.temporaryDirectory.appendingPathComponent("speek-codex-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: logURL)
            try? FileManager.default.removeItem(at: finalURL)
        }

        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("speek-task-\(UUID().uuidString).jpg")
        var imageArguments: [String] = []
        if let image { try image.write(to: imageURL); imageArguments = ["-i", imageURL.path] }
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.environment = try CodexConnection.environment(for: connection)
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let common = ["--skip-git-repo-check", "-c", "model_provider=\"openai\"", "-c", "approval_policy=\"never\"", "-c", "sandbox_mode=\"workspace-write\"", "--json", "-o", finalURL.path] + ["--model", modelID ?? AgentDefaults.model(for: connection)] + (reasoningEffort.map { ["-c", "model_reasoning_effort=\"\($0)\""] } ?? [])
        if let sessionID {
            process.arguments = ["exec", "resume", sessionID] + common + imageArguments + ["--", prompt]
        } else {
            process.arguments = ["exec", "-C", directory, "-s", "workspace-write"] + common + imageArguments + ["--", prompt]
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = logHandle
        process.standardError = logHandle
        defer { try? logHandle.close() }

        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { task in continuation.resume(returning: task.terminationStatus) }
                do { try process.run() }
                catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let events = log.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let newSessionID = events.first(where: { $0["type"] as? String == "thread.started" })?["thread_id"] as? String
        let finalMessage = ((try? String(contentsOf: finalURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0 else {
            let errorText = events.compactMap { $0["message"] as? String }.last
            throw CodexJobError.failed(errorText ?? "Codex exited with status \(status).")
        }
        return (finalMessage.isEmpty ? "Codex finished. Check the project for changes." : finalMessage, newSessionID ?? sessionID)
    }
}
