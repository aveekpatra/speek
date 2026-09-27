import Foundation

/// Runs a command in the user's login shell. Governed by Integrations > Approvals like every
/// other tool (default: Ask, because a command can change anything).
enum ShellTool {
    static let id = "shell.run"
    static let timeout: TimeInterval = 60
    static let outputLimit = 20_000

    @MainActor static var tool: RuntimeTool {
        RuntimeTool(id: id, title: "Run a shell command",
                    summary: "Run a command in the user's login shell (zsh) on this Mac and return exit code and output. Use for command-line tools, including CLIs documented by enabled skills. Runs in the working folder, or the home folder if none is set. 60-second limit; output is truncated after 20,000 characters.",
                    schema: ActionRuntime.schema(["command": ["type": "string"], "workingDirectory": ["type": "string"]], required: ["command"]),
                    requiresReview: true)
    }

    static func execute(arguments: [String: Any]) async throws -> String {
        guard let command = (arguments["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            throw ActionClientError.requestFailed("Enter a command.")
        }
        let directory = resolvedDirectory(arguments["workingDirectory"] as? String)
        return try await Task.detached(priority: .userInitiated) { try run(command, in: directory) }.value
    }

    private static func resolvedDirectory(_ requested: String?) -> String {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        for candidate in [requested, UserDefaults.standard.string(forKey: "speek.actions.projectFolder")].compactMap({ $0 }) {
            let path = (candidate as NSString).expandingTildeInPath
            if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue { return path }
        }
        return NSHomeDirectory()
    }

    private static func run(_ command: String, in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let collected = OutputBuffer(limit: outputLimit)
        output.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let timedOut = process.isRunning
        if timedOut { process.terminate(); Thread.sleep(forTimeInterval: 0.3); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        collected.append(output.fileHandleForReading.readDataToEndOfFile())
        var text = "Directory: \(directory)\nExit code: \(process.terminationStatus)\(timedOut ? " (stopped after \(Int(timeout)) seconds)" : "")\n"
        text += collected.text.isEmpty ? "(no output)" : collected.text
        return text
    }
}

/// Thread-safe capped collector for process output.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    private let limit: Int
    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard data.count < limit * 4 else { truncated = true; return }
        data.append(chunk)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        let value = String(decoding: data, as: UTF8.self)
        guard value.count > limit || truncated else { return value }
        return String(value.prefix(limit)) + "\n[Output truncated]"
    }
}
