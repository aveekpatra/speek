import Foundation

@main
struct ComputerTaskChecks {
    @MainActor static func main() async throws {
        let manager = ComputerTaskManager()
        var release: CheckedContinuation<Void, Never>?
        var started: [String] = []
        var completed: [ComputerTaskJob] = []
        let source = UUID()
        let first = manager.enqueue(request: "First", sourceThreadID: source, operation: { progress in
            started.append("first")
            progress("Working")
            await withCheckedContinuation { release = $0 }
            return "First result"
        }, completed: { completed.append($0) })
        let second = manager.enqueue(request: "Second", sourceThreadID: UUID(), operation: { _ in
            started.append("second")
            return "Second result"
        }, completed: { completed.append($0) })
        let cancelled = manager.enqueue(request: "Cancelled", sourceThreadID: nil, operation: { _ in
            fatalError("Cancelled queued work must never run")
        }, completed: { completed.append($0) })
        for _ in 0..<20 where release == nil { await Task.yield() }
        precondition(started == ["first"])
        // Independent foreground work must run while computer work is suspended.
        var foregroundFinished = false
        let foreground = Task { @MainActor in foregroundFinished = true }
        await foreground.value
        precondition(foregroundFinished)
        manager.cancel(cancelled)
        release?.resume()
        for _ in 0..<100 where completed.count < 3 { await Task.yield() }
        precondition(started == ["first", "second"])
        precondition(completed.count == 3)
        precondition(completed.first { $0.id == first }?.sourceThreadID == source)
        precondition(completed.first { $0.id == first }?.result == "First result")
        precondition(completed.first { $0.id == second }?.status == .completed)

        var cancellationStarted = false
        let running = manager.enqueue(request: "Running cancellation", sourceThreadID: nil, operation: { _ in
            cancellationStarted = true
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return "Must not finish"
        }, completed: { completed.append($0) })
        for _ in 0..<100 where !cancellationStarted { await Task.yield() }
        precondition(cancellationStarted)
        manager.cancel(running)
        _ = manager.enqueue(request: "After cancellation", sourceThreadID: nil, operation: { _ in "Still usable" }, completed: { completed.append($0) })
        for _ in 0..<1000 where completed.count < 5 { await Task.yield() }
        precondition(completed.filter { $0.id == running }.count == 1)
        precondition(completed.last?.result == "Still usable")
        print("PASS: independent foreground work, serial desktop queue, source routing, queued/running cancellation, queue recovery")
    }
}
