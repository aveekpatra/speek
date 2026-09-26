import Foundation
@main struct Checks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent("activity.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let scheduler = TaskScheduler(fileURL: file)
        let first = scheduler.enqueue(title: "Queued", request: "Read")
        let restored = TaskScheduler(fileURL: file)
        assert(restored.jobs.first?.status == .interrupted)
        restored.retryJob(first)
        assert(restored.jobs.first?.status == .awaitingReview)
        restored.cancelJob(first)
        assert(restored.jobs.first?.status == .cancelled)
        let due = Date().addingTimeInterval(60)
        try restored.addSchedule(title: "Review", request: "Check", date: due, recurrence: .daily)
        restored.checkDueSchedules(now: due.addingTimeInterval(1))
        assert(restored.jobs.filter { $0.status == .awaitingReview }.count == 1)
        restored.checkDueSchedules(now: due.addingTimeInterval(3 * 86400))
        assert(restored.jobs.filter { $0.status == .awaitingReview }.count == 1)
        let pending = restored.jobs.first { $0.status == .awaitingReview }!.id
        assert(!restored.reviewJob(pending))
        restored.onReviewRequest = { _ in false }
        assert(!restored.reviewJob(pending))
        assert(restored.jobs.first { $0.id == pending }?.status == .awaitingReview)
        var handoffs = 0
        restored.onReviewRequest = { _ in handoffs += 1; return true }
        assert(restored.reviewJob(pending))
        assert(restored.jobs.first { $0.id == pending }?.status == .handedOff)
        assert(!restored.reviewJob(pending))
        assert(handoffs == 1)
        let afterHandoff = TaskScheduler(fileURL: file)
        assert(afterHandoff.jobs.first { $0.id == pending }?.status == .handedOff)
        afterHandoff.checkDueSchedules(now: due.addingTimeInterval(5 * 86400))
        assert(afterHandoff.jobs.filter { $0.status == .awaitingReview }.count == 1)
        assert(afterHandoff.jobs.filter { $0.scheduleID != nil }.count == 2)
        let formatter = ISO8601DateFormatter()
        let schedule = TaskSchedule(title: "DST", request: "Check", nextRun: formatter.date(from:"2026-03-28T09:00:00+01:00")!, recurrence: .daily, timeZone: "Europe/Prague")
        let next = schedule.followingRun(after: schedule.nextRun)!
        assert(next == formatter.date(from:"2026-03-29T09:00:00+02:00")!)
        let weekly = TaskSchedule(title: "Weekly", request: "Check", nextRun: schedule.nextRun, recurrence: .weekly, timeZone: "Europe/Prague")
        assert(weekly.followingRun(after: schedule.nextRun)! == formatter.date(from:"2026-04-04T09:00:00+02:00")!)
        let runFile = folder.appendingPathComponent("run.json")
        let running = TaskScheduler(fileURL: runFile)
        running.start { _ in try await Task.sleep(for: .milliseconds(80)); return "done" }
        let id = running.enqueue(title: "Cancel", request: "Read")
        running.cancelJob(id)
        try await Task.sleep(for: .milliseconds(120))
        assert(running.jobs.first?.status == .cancelled)
        running.stop()
        print("PASS: restart safety, retry review, cancellation, due review, repeat coalescing, rejected/accepted/persisted handoff, recurrence after handoff, daily DST, weekly rollover")
    }
}
