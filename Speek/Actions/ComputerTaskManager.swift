import Foundation
import Combine

struct ComputerTaskJob: Identifiable {
    enum Status: String { case queued, running, completed, failed, cancelled }
    let id = UUID()
    let request: String
    let sourceThreadID: UUID?
    var status: Status = .queued
    var progress = "Queued"
    var result: String?
}

/// Owns computer work independently of the recorder and foreground conversation.
/// Only one job controls the shared desktop at a time.
@MainActor
final class ComputerTaskManager: ObservableObject {
    static let shared = ComputerTaskManager()
    @Published private(set) var jobs: [ComputerTaskJob] = []
    typealias Operation = @MainActor (@escaping (String) -> Void) async throws -> String
    private var operations: [UUID: Operation] = [:]
    private var completions: [UUID: (ComputerTaskJob) -> Void] = [:]
    private var worker: Task<Void, Never>?
    private var runningID: UUID?

    var currentJob: ComputerTaskJob? { jobs.first { $0.id == runningID } }

    @discardableResult
    func enqueue(request: String, sourceThreadID: UUID?, operation: @escaping Operation,
                 completed: @escaping (ComputerTaskJob) -> Void) -> UUID {
        let job = ComputerTaskJob(request: request, sourceThreadID: sourceThreadID)
        jobs.append(job)
        operations[job.id] = operation
        completions[job.id] = completed
        drain()
        return job.id
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              [.queued, .running].contains(jobs[index].status) else { return }
        jobs[index].status = .cancelled
        jobs[index].progress = "Cancelled"
        jobs[index].result = "Computer task cancelled. Actions already completed were not undone."
        if runningID == id { worker?.cancel() }
        else { operations[id] = nil }
        completions.removeValue(forKey: id)?(jobs[index])
        // The active worker retains the desktop until cancellation has unwound.
        if runningID == nil { drain() }
    }

    func dismiss(_ id: UUID) {
        jobs.removeAll { $0.id == id && ![.queued, .running].contains($0.status) }
    }

    private func drain() {
        guard worker == nil,
              let job = jobs.first(where: { $0.status == .queued }),
              let operation = operations.removeValue(forKey: job.id) else { return }
        runningID = job.id
        update(job.id) { $0.status = .running; $0.progress = "Starting" }
        worker = Task { [self] in
            do {
                let result = try await operation { [weak self] progress in
                    self?.update(job.id) { if $0.status == .running { $0.progress = progress } }
                }
                try Task.checkCancellation()
                update(job.id) { $0.status = .completed; $0.progress = "Completed"; $0.result = result }
            } catch {
                update(job.id) {
                    guard $0.status != .cancelled else { return }
                    $0.status = error is CancellationError ? .cancelled : .failed
                    $0.progress = $0.status == .cancelled ? "Cancelled" : "Needs attention"
                    $0.result = error.localizedDescription
                }
            }
            if let finished = jobs.first(where: { $0.id == job.id }) {
                completions.removeValue(forKey: job.id)?(finished)
            }
            runningID = nil
            worker = nil
            drain()
        }
    }

    private func update(_ id: UUID, _ change: (inout ComputerTaskJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}
