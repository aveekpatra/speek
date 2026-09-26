import Foundation
import Combine
import UserNotifications

struct BackgroundJob: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case awaitingReview, queued, running, handedOff, completed, failed, cancelled, interrupted }
    var id = UUID()
    var title: String
    var request: String
    var status: Status
    var createdAt = Date()
    var updatedAt = Date()
    var result: String?
    var error: String?
    var scheduleID: UUID?
    var providerRaw: String?
    var modelID: String?
    var reasoningEffort: String?
    var pendingProposalJSON: String?
    var reviewEvidence: [String]?
}

struct TaskSchedule: Codable, Identifiable, Sendable {
    enum Recurrence: String, CaseIterable, Codable, Identifiable, Sendable {
        case once, daily, weekly
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    var id = UUID()
    var title: String
    var request: String
    var nextRun: Date
    var recurrence: Recurrence
    var timeZone: String
    var paused = false
    var lastRun: Date?
    var providerRaw: String?
    var modelID: String?
    var reasoningEffort: String?

    /// Calendar arithmetic preserves local wall time across daylight saving changes.
    func followingRun(after now: Date) -> Date? {
        guard recurrence != .once else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let components = calendar.dateComponents([.hour, .minute, .second, .weekday], from: nextRun)
        var match = DateComponents()
        match.hour = components.hour; match.minute = components.minute; match.second = components.second
        if recurrence == .weekly { match.weekday = components.weekday }
        return calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

@MainActor
final class TaskScheduler: ObservableObject {
    static let shared = TaskScheduler()
    @Published private(set) var jobs: [BackgroundJob] = []
    @Published private(set) var schedules: [TaskSchedule] = []
    @Published private(set) var storageError: String?
    @Published private(set) var notificationsEnabled = false
    var onReviewRequest: ((BackgroundJob) -> Bool)?
    private var executor: ((BackgroundJob) async throws -> String)?
    private var runner: Task<Void, Never>?
    private var timer: Timer?
    private let fileURL: URL
    private var loadFailed = false
    private struct State: Codable { var jobs: [BackgroundJob]; var schedules: [TaskSchedule] }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speek", isDirectory: true).appendingPathComponent("activity.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: self.fileURL))
            jobs = state.jobs; schedules = state.schedules
            for index in jobs.indices where jobs[index].providerRaw == nil {
                jobs[index].providerRaw = ActionConnection.preferred.rawValue
                jobs[index].modelID = AgentDefaults.model(for: ActionConnection.preferred)
                jobs[index].reasoningEffort = AgentDefaults.reasoning(for: ActionConnection.preferred)
            }
            for index in schedules.indices where schedules[index].providerRaw == nil {
                schedules[index].providerRaw = ActionConnection.preferred.rawValue
                schedules[index].modelID = AgentDefaults.model(for: ActionConnection.preferred)
                schedules[index].reasoningEffort = AgentDefaults.reasoning(for: ActionConnection.preferred)
            }
            for index in jobs.indices where jobs[index].status == .running || jobs[index].status == .queued {
                jobs[index].status = .interrupted
                jobs[index].error = "Speek stopped before this task finished. Review it before retrying to avoid repeating an action."
                jobs[index].updatedAt = Date()
            }
            _ = persist()
        } catch {
            loadFailed = true
            storageError = "Activity could not be loaded. The existing file was preserved: \(error.localizedDescription)"
        }
    }

    func start(executor: @escaping (BackgroundJob) async throws -> String) {
        self.executor = executor
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDueSchedules() }
        }
        checkDueSchedules()
        drain()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        runner?.cancel(); runner = nil
        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .interrupted; jobs[index].updatedAt = Date()
        }
        _ = persist()
    }

    @discardableResult func enqueue(title: String, request: String, connection: ActionConnection = .preferred, modelID: String? = nil, reasoningEffort: String? = nil) -> UUID {
        let job = BackgroundJob(title: title, request: request, status: .queued, providerRaw: connection.rawValue, modelID: modelID ?? AgentDefaults.model(for: connection), reasoningEffort: reasoningEffort ?? AgentDefaults.reasoning(for: connection))
        jobs.insert(job, at: 0)
        if persist() { drain() }
        return job.id
    }

    func approveJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .awaitingReview else { return }
        guard jobs[index].pendingProposalJSON == nil else { reviewJob(id); return }
        jobs[index].status = .queued; jobs[index].updatedAt = Date()
        if persist() { drain() }
    }

    @discardableResult func reviewJob(_ id: UUID) -> Bool {
        guard !loadFailed, storageError == nil,
              let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].status == .awaitingReview,
              onReviewRequest?(jobs[index]) == true else { return false }
        // The foreground chat owns the request now. This is not execution success.
        jobs[index].status = .handedOff
        jobs[index].updatedAt = Date()
        _ = persist()
        return true
    }

    func cancelJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), [.queued, .running, .awaitingReview].contains(jobs[index].status) else { return }
        let wasRunning = jobs[index].status == .running
        jobs[index].status = .cancelled; jobs[index].updatedAt = Date()
        if wasRunning { runner?.cancel() }
        _ = persist()
    }

    func retryJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), [.failed, .interrupted, .cancelled].contains(jobs[index].status) else { return }
        jobs[index].status = .awaitingReview
        jobs[index].error = nil; jobs[index].updatedAt = Date()
        _ = persist()
    }

    func deleteJob(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.status != .running else { return }
        jobs.removeAll { $0.id == id }
        _ = persist()
    }

    func addSchedule(title: String, request: String, date: Date, recurrence: TaskSchedule.Recurrence, timeZone: String = TimeZone.current.identifier) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              date > Date(), TimeZone(identifier: timeZone) != nil else {
            throw NSError(domain: "TaskScheduler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a title, instructions, and a future date in a valid time zone."])
        }
        let connection = ActionConnection.preferred
        let schedule = TaskSchedule(title: title, request: request, nextRun: date, recurrence: recurrence, timeZone: timeZone, providerRaw: connection.rawValue, modelID: AgentDefaults.model(for: connection), reasoningEffort: AgentDefaults.reasoning(for: connection))
        schedules.append(schedule)
        guard persist() else {
            schedules.removeAll { $0.id == schedule.id }
            throw NSError(domain: "TaskScheduler", code: 2, userInfo: [NSLocalizedDescriptionKey: storageError ?? "Could not save schedule."])
        }
    }

    func setSchedulePaused(_ id: UUID, paused: Bool) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].paused = paused
        if persist(), !paused { checkDueSchedules() }
    }
    func deleteSchedule(_ id: UUID) { schedules.removeAll { $0.id == id }; _ = persist() }

    func checkDueSchedules(now: Date = Date()) {
        guard !loadFailed, storageError == nil else { return }
        let previousJobs = jobs, previousSchedules = schedules
        var newJobs: [BackgroundJob] = []
        for index in schedules.indices where !schedules[index].paused && schedules[index].nextRun <= now {
            let schedule = schedules[index]
            let job = BackgroundJob(title: schedule.title, request: schedule.request, status: .awaitingReview, scheduleID: schedule.id, providerRaw: schedule.providerRaw, modelID: schedule.modelID, reasoningEffort: schedule.reasoningEffort)
            // A pending occurrence already asks for the same work. Coalesce missed repeats.
            if !jobs.contains(where: { $0.scheduleID == schedule.id && [.awaitingReview, .queued, .running].contains($0.status) }) {
                jobs.insert(job, at: 0); newJobs.append(job)
            }
            schedules[index].lastRun = now
            if let next = schedule.followingRun(after: now) { schedules[index].nextRun = next }
            else { schedules[index].paused = true }
        }
        guard !newJobs.isEmpty || schedules.contains(where: { $0.lastRun == now }) else { return }
        guard persist() else { jobs = previousJobs; schedules = previousSchedules; return }
        for job in newJobs { notify(title: "Ready to review", body: job.title, id: job.id) }
    }

    func requestNotificationAccess() async throws {
        notificationsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func drain() {
        guard runner == nil, let executor, !loadFailed, storageError == nil,
              let index = jobs.lastIndex(where: { $0.status == .queued }) else { return }
        jobs[index].status = .running; jobs[index].updatedAt = Date()
        let job = jobs[index]
        guard persist() else { jobs[index].status = .queued; return }
        runner = Task { @MainActor [weak self] in
            do {
                let result = try await executor(job)
                try Task.checkCancellation()
                self?.finish(job.id, result: result, error: nil)
            } catch {
                self?.finish(job.id, result: nil, error: error)
            }
            self?.runner = nil
            self?.drain()
        }
    }

    private func finish(_ id: UUID, result: String?, error: Error?) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .running else { return }
        if let review = error as? BackgroundActionNeedsReview {
            jobs[index].status = .awaitingReview
            jobs[index].pendingProposalJSON = review.proposalJSON
            jobs[index].reviewEvidence = review.evidence
            jobs[index].error = nil; jobs[index].updatedAt = Date()
            if persist() { notify(title: "Ready to review", body: jobs[index].title, id: id) }
            return
        }
        jobs[index].status = error == nil ? .completed : (error is CancellationError ? .cancelled : .failed)
        jobs[index].result = result; jobs[index].error = error?.localizedDescription; jobs[index].updatedAt = Date()
        guard persist() else { return }
        if jobs[index].status != .cancelled { notify(title: error == nil ? "Task complete" : "Task needs attention", body: jobs[index].title, id: id) }
    }

    @discardableResult private func persist() -> Bool {
        guard !loadFailed else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(State(jobs: jobs, schedules: schedules))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageError = nil
            return true
        } catch { storageError = "Activity could not be saved: \(error.localizedDescription)"; return false }
    }

    private func notify(title: String, body: String, id: UUID) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            content.userInfo = ["speekActivityID": id.uuidString]
            try? await center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        }
    }
}
