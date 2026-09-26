import Foundation
@main struct CodingChecks {
    @MainActor static func main() async throws {
        let cases: [(String, CodingTaskJob.Engine, CodingProgressEvent)] = [
            (#"{"type":"thread.started","thread_id":"abc"}"#, .codex, .init(sessionID: "abc")),
            (#"{"type":"item.completed","item":{"type":"agent_message","text":"Done"}}"#, .codex, .init(text: "Done")),
            (#"{"type":"item.started","item":{"type":"command_execution","command":"swift test"}}"#, .codex, .init(text: "Command: swift test")),
            (#"{"type":"item.completed","item":{"type":"file_change","changes":[{"path":"a.swift"}]}}"#, .codex, .init(text: "Files: a.swift")),
            (#"{"type":"turn.failed","error":{"message":"Rate limited"}}"#, .codex, .init(failure: "Rate limited")),
            (#"{"type":"system","subtype":"init","session_id":"xyz"}"#, .claude, .init(sessionID: "xyz")),
            (#"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading"},{"type":"tool_use","name":"Read"}]}}"#, .claude, .init(text: "Reading\nTool: Read")),
            (#"{"type":"result","is_error":false,"result":"Finished","session_id":"xyz"}"#, .claude, .init(sessionID: "xyz", result: "Finished")),
            (#"{"type":"result","is_error":true,"result":"Denied"}"#, .claude, .init(failure: "Denied"))
        ]
        for (line, engine, expected) in cases { assert(CodingProgressEvent.parse(line, engine: engine) == expected) }
        assert(CodingProgressEvent.parse("malformed", engine: .codex) == nil)
        assert(CodingTaskManager.pathsOverlap("/tmp/project", "/tmp/project/subdir"))
        assert(!CodingTaskManager.pathsOverlap("/tmp/project", "/tmp/project-other"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = folder.appendingPathComponent("project"), other = folder.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        var running = Set<String>(), maxParallel = 0
        let manager = CodingTaskManager(folder: folder.appendingPathComponent("state")) { job, progress in
            assert(!running.contains(job.directory)); running.insert(job.directory); maxParallel = max(maxParallel, running.count)
            defer { running.remove(job.directory) }
            progress(.init(sessionID: job.id.uuidString, text: "started"))
            try await Task.sleep(for: .milliseconds(job.request == "first" ? 160 : 40))
            return "done"
        }
        do { try manager.enqueue(request: "first", directory: project.path, approved: false); assertionFailure() } catch {}
        assert(manager.jobs.isEmpty)
        let first = try manager.enqueue(request: "first", directory: project.path, approved: true)
        let second = try manager.enqueue(request: "second", directory: project.path, approved: true)
        let independent = try manager.enqueue(request: "independent", directory: other.path, approved: true)
        assert(manager.jobs.filter { $0.status == .running }.count == 2)
        assert(manager.jobs.first { $0.id == second }?.status == .queued)
        try await Task.sleep(for: .milliseconds(80))
        assert(manager.jobs.first { $0.id == independent }?.status == .completed)
        assert(manager.jobs.first { $0.id == second }?.status == .queued)
        try await Task.sleep(for: .milliseconds(200))
        assert(manager.jobs.first { $0.id == first }?.status == .completed)
        assert(manager.jobs.first { $0.id == second }?.status == .completed)
        assert(maxParallel == 2)
        let cancel = try manager.enqueue(request: "first", directory: project.path, approved: true)
        manager.cancel(cancel)
        try await Task.sleep(for: .milliseconds(80))
        assert(manager.jobs.first { $0.id == cancel }?.status == .cancelled)
        let restartFolder = folder.appendingPathComponent("restart")
        try FileManager.default.createDirectory(at: restartFolder, withIntermediateDirectories: true)
        var interrupted = manager.jobs[0]; interrupted.status = .running
        try JSONEncoder().encode([interrupted]).write(to: restartFolder.appendingPathComponent("jobs.json"))
        let restored = CodingTaskManager(folder: restartFolder)
        assert(restored.jobs.first?.status == .interrupted)
        do { try manager.enqueue(request: "resume", directory: other.path, sessionID: first.uuidString, approved: true); assertionFailure() } catch {}
        print("PASS: Codex/Claude event fixtures, mutation review, parallel2 limit, same-folder serialization, cancellation, interrupted restore, session folder binding")
    }
}
