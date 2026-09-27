import Foundation
import Darwin

actor MCPStdioTransport: MCPTransport {
    private let process: Process
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writer = DispatchQueue(label: "com.aveekpatra.speek.mcp-stdin")
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<MCPValue, Error>] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var version = MCPProtocol.legacy
    private var started = false
    private var closed = false
    private var serverRequestHandler: MCPServerRequestHandler?

    func setServerRequestHandler(_ handler: MCPServerRequestHandler?) async { serverRequestHandler = handler }

    init(executable: String, arguments: [String], workingDirectory: String, environment: [String: String]) throws {
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
            throw MCPError.invalidConfiguration("Choose the absolute path of an installed executable.")
        }
        process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Inherit only basic operating-system context. Never forward unrelated API keys.
        let allowed = ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "SHELL"]
        var variables = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        variables["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        variables.merge(environment) { _, explicit in explicit }
        process.environment = variables
        if !workingDirectory.isEmpty {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &directory), directory.boolValue else {
                throw MCPError.invalidConfiguration("The working folder does not exist.")
            }
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
    }

    private func start() throws {
        guard !closed else { throw MCPError.disconnected }
        guard !started else { return }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data) }
        }
        // Drain stderr so servers cannot block. Never persist potentially sensitive logs.
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] _ in Task { await self?.terminated() } }
        do { try process.run(); started = true }
        catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw MCPError.invalidConfiguration("The local server could not start. Check its executable and arguments.")
        }
    }

    func setProtocolVersion(_ version: String) { self.version = version }

    func request(method: String, params: MCPValue) async throws -> MCPValue {
        try start()
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timers[id] = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: (method == "server/discover" ? 5_000_000_000 : 90_000_000_000)) }
                    catch { return }
                    await self?.cancel(id: id, error: MCPError.timeout)
                }
                do {
                    try write(.object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": MCPProtocol.parameters(params, version: version)]))
                } catch { finish(id: id, result: .failure(error)) }
            }
        } onCancel: {
            Task { await self.cancel(id: id, error: CancellationError()) }
        }
    }

    func notify(method: String, params: MCPValue) async throws {
        try start()
        try write(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": MCPProtocol.parameters(params, version: version)]))
    }

    private func writeResponse(_ value: MCPValue) throws { try write(value) }

    private func write(_ value: MCPValue) throws {
        guard !closed, process.isRunning else { throw MCPError.disconnected }
        var data = try JSONEncoder().encode(value)
        guard data.count < 4 * 1024 * 1024 else { throw MCPError.invalidConfiguration("The tool request is too large.") }
        data.append(0x0A)
        let handle = input.fileHandleForWriting
        let encoded = data
        writer.async { [weak self] in
            do { try handle.write(contentsOf: encoded) }
            catch { Task { await self?.terminated() } }
        }
    }

    private func receive(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty else { terminated(); return }
        buffer.append(data)
        guard buffer.count <= 8 * 1024 * 1024 else { terminated(); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let value = try? JSONDecoder().decode(MCPValue.self, from: line) else {
                terminated(); return
            }
            if let method = value["method"]?.string, let requestID = value["id"] {
                guard version != MCPProtocol.current else { terminated(); return }
                let handler = serverRequestHandler
                let params = value["params"] ?? .object([:])
                Task { [weak self] in
                    let response = await mcpServerResponse(id: requestID, method: method, params: params, handler: handler)
                    try? await self?.writeResponse(response)
                }
            } else if let id = value["id"]?.string, pending[id] != nil {
                do {
                    guard let result = try mcpResult(from: line, matching: .string(id)) else { throw MCPError.invalidResponse }
                    finish(id: id, result: .success(result))
                } catch { finish(id: id, result: .failure(error)) }
            }
        }
    }

    private func finish(id: String, result: Result<MCPValue, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func cancel(id: String, error: Error) {
        guard pending[id] != nil else { return }
        try? write(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"),
                            "params": .object(["requestId": .string(id), "reason": .string("Request cancelled")])]))
        finish(id: id, result: .failure(error))
    }

    private func terminated() {
        for id in Array(pending.keys) { finish(id: id, result: .failure(MCPError.disconnected)) }
        closed = true
        stopProcess()
        closeHandles()
    }

    func close() async {
        guard !closed else { return }
        closed = true
        for id in Array(pending.keys) { finish(id: id, result: .failure(CancellationError())) }
        stopProcess()
        closeHandles()
    }

    private func stopProcess() {
        if process.isRunning {
            process.terminate()
            let child = process
            Task.detached {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    private func closeHandles() {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        let handle = input.fileHandleForWriting
        writer.async { try? handle.close() }
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
    }
}
