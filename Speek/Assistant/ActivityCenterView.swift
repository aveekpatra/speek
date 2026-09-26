import SwiftUI
import AppKit

struct ActivityCenterView: View {
    @ObservedObject private var scheduler = TaskScheduler.shared
    @State private var selected = "Jobs"
    @State private var creating = false
    @State private var reviewing: BackgroundJob?
    @State private var title = ""
    @State private var instructions = ""
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var recurrence = TaskSchedule.Recurrence.once
    @State private var error: String?
    @State private var notificationBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity").font(.system(size: 25, weight: .semibold))
                    Text("Background tasks and scheduled requests.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(["Jobs", "Schedules"], id: \.self) { name in
                        Button { selected = name } label: {
                            Text(name).font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(selected == name ? Color.white.opacity(0.11) : .clear, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(selected == name ? .isSelected : [])
                    }
                }.padding(4).frame(maxWidth: 360).background(.black.opacity(0.12), in: Capsule())
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(selected).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if selected == "Schedules" {
                            Button { error = nil; creating = true } label: { Label("Add schedule", systemImage: "plus") }
                                .buttonStyle(SpeekActionButtonStyle())
                        }
                    }
                    if selected == "Jobs" { jobsContent } else { schedulesContent }
                }
                if let storageError = scheduler.storageError { errorLabel(storageError) }
                if let error { errorLabel(error) }
                HStack(alignment: .center, spacing: 12) {
                    Text("Schedules become requests to review. Speek must be running; missed repeats are combined when you return.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Notifications") {
                        notificationBusy = true
                        Task {
                            do { try await scheduler.requestNotificationAccess() }
                            catch { self.error = error.localizedDescription }
                            notificationBusy = false
                        }
                    }.buttonStyle(SpeekActionButtonStyle()).disabled(notificationBusy)
                }
            }.frame(maxWidth: 880, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $creating) { scheduleEditor }
        .sheet(item: $reviewing) { job in review(job) }
    }

    @ViewBuilder private var jobsContent: some View {
        if scheduler.jobs.isEmpty {
            empty("No background tasks", detail: "Agent tasks and scheduled requests appear here with their progress and results.", symbol: "tray")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(scheduler.jobs.sorted { $0.createdAt > $1.createdAt }) { job in backgroundCard(job) }
            }
        }
    }

    private func backgroundCard(_ job: BackgroundJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(job.status)).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.system(size: 13, weight: .medium))
                    Text(status(job.status)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(job.updatedAt, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let failure = job.error { errorLabel(failure) }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(job.request).textSelection(.enabled)
                    if let result = job.result { Divider(); Text(result).textSelection(.enabled) }
                }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.system(size: 11))
            HStack(spacing: 8) {
                Spacer()
                if job.status == .awaitingReview {
                    if job.pendingProposalJSON != nil {
                        Button("Open in chat") { _ = scheduler.reviewJob(job.id) }.buttonStyle(SpeekActionButtonStyle())
                    } else {
                        Button("Review") { reviewing = job }.buttonStyle(SpeekActionButtonStyle())
                    }
                }
                if [.running, .queued, .awaitingReview].contains(job.status) {
                    Button("Cancel") { scheduler.cancelJob(job.id) }.buttonStyle(SpeekActionButtonStyle())
                } else if [.failed, .cancelled, .interrupted].contains(job.status) {
                    Button("Review retry") { scheduler.retryJob(job.id); reviewing = scheduler.jobs.first { $0.id == job.id } }
                        .buttonStyle(SpeekActionButtonStyle())
                }
                if job.status != .running {
                    Button("Remove", role: .destructive) { scheduler.deleteJob(job.id) }.buttonStyle(SpeekActionButtonStyle())
                }
            }
        }.padding(20).settingsSurface()
    }


    @ViewBuilder private var schedulesContent: some View {
        if scheduler.schedules.isEmpty {
            empty("No schedules", detail: "Choose when to revisit a task. Each occurrence waits for your review before it runs.", symbol: "calendar")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(scheduler.schedules) { schedule in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "calendar").frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(schedule.title).font(.system(size: 13, weight: .medium))
                                Text(schedule.paused ? "Paused" : "\(schedule.recurrence.title) - \(schedule.nextRun.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(schedule.timeZone).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Text(schedule.request).font(.system(size: 13)).lineLimit(3)
                        HStack(spacing: 8) {
                            Spacer()
                            Button(schedule.paused ? "Resume" : "Pause") { scheduler.setSchedulePaused(schedule.id, paused: !schedule.paused) }
                                .buttonStyle(SpeekActionButtonStyle())
                            Button("Remove", role: .destructive) { scheduler.deleteSchedule(schedule.id) }.buttonStyle(SpeekActionButtonStyle())
                        }
                    }.padding(20).settingsSurface()
                }
            }
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New schedule").font(.system(size: 20, weight: .semibold))
            Text("At the scheduled time, this request will be ready for you to review.").font(.system(size: 13)).foregroundStyle(.secondary)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextEditor(text: $instructions).font(.system(size: 13)).frame(height: 100)
                    .padding(8).background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack { Text("When"); Spacer(); DatePicker("When", selection: $scheduledDate, in: Date()..., displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
            HStack {
                Text("Repeat"); Spacer()
                Picker("Repeat", selection: $recurrence) { ForEach(TaskSchedule.Recurrence.allCases) { Text($0.title).tag($0) } }.labelsHidden().fixedSize()
            }
            Text("Time zone: \(TimeZone.current.identifier)").font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { errorLabel(error) }
            HStack {
                Spacer()
                Button("Cancel") { creating = false }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try scheduler.addSchedule(title: title, request: instructions, date: scheduledDate, recurrence: recurrence)
                        creating = false; title = ""; instructions = ""; error = nil
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.font(.system(size: 13)).padding(24).frame(width: 480)
    }

    private func review(_ job: BackgroundJob) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(job.title).font(.system(size: 20, weight: .semibold))
            ScrollView { Text(job.request).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(maxHeight: 240)
            Text("Running this request starts the agent. Individual changes still require approval. Check whether an interrupted task already made changes before retrying.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { reviewing = nil }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Run request") { scheduler.approveJob(job.id); reviewing = nil }.buttonStyle(SpeekActionButtonStyle())
            }
        }.padding(24).frame(width: 480)
    }

    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).settingsSurface()
    }
    private func errorLabel(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
    private func status(_ value: BackgroundJob.Status) -> String {
        switch value {
        case .awaitingReview: return "Ready to review"
        case .queued: return "Queued"
        case .running: return "Running"
        case .handedOff: return "Opened in chat"
        case .completed: return "Completed"
        case .failed: return "Needs attention"
        case .cancelled: return "Cancelled"
        case .interrupted: return "Interrupted"
        }
    }
    private func symbol(_ value: BackgroundJob.Status) -> String {
        switch value {
        case .awaitingReview: return "checklist"
        case .queued: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .handedOff: return "bubble.left"
        case .completed: return "checkmark.circle.fill"
        case .failed, .interrupted: return "exclamationmark.circle"
        case .cancelled: return "xmark.circle"
        }
    }
}
