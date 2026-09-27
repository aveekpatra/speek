import SwiftUI

/// Creates or edits a scheduled request. Each occurrence opens in a new chat for review.
struct ScheduleEditorSheet: View {
    let schedule: TaskSchedule?
    var initialRequest = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var scheduler = TaskScheduler.shared
    @State private var title = ""
    @State private var request = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var recurrence = TaskSchedule.Recurrence.once
    @State private var error: String?

    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(schedule == nil ? "New schedule" : "Edit schedule").font(.system(size: 17, weight: .semibold))
                InfoButton(text: "At the scheduled time, Speek opens this request in a new chat for you to review. Speek must be running; missed repeats are combined.", subject: "Schedules")
            }
            field("Title") { TextField("Morning inbox summary", text: $title) }
            field("Request") { TextField("What should Speek do?", text: $request, axis: .vertical).lineLimit(3...8) }
            HStack {
                Text("When").font(.system(size: 13))
                Spacer()
                DatePicker("When", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
            }
            HStack {
                Text("Repeat").font(.system(size: 13))
                Spacer()
                Picker("Repeat", selection: $recurrence) { ForEach(TaskSchedule.Recurrence.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize()
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                if let schedule {
                    Button("Delete", role: .destructive) { scheduler.deleteSchedule(schedule.id); dismiss() }
                        .buttonStyle(SpeekActionButtonStyle())
                    Button(schedule.paused ? "Resume" : "Pause") { scheduler.setSchedulePaused(schedule.id, paused: !schedule.paused); dismiss() }
                        .buttonStyle(SpeekActionButtonStyle())
                }
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(clean(title).isEmpty || clean(request).isEmpty)
            }
        }
        .padding(24).frame(width: 480)
        .onAppear {
            if let schedule {
                title = schedule.title; request = schedule.request; recurrence = schedule.recurrence
                date = max(schedule.nextRun, Date().addingTimeInterval(60))
            } else {
                request = initialRequest
                title = String(clean(initialRequest).prefix(60))
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium))
            content().textFieldStyle(.roundedBorder).font(.system(size: 13))
        }
    }

    private func save() {
        do {
            if let schedule {
                try scheduler.updateSchedule(schedule.id, title: clean(title), request: clean(request), date: date, recurrence: recurrence)
            } else {
                try scheduler.addSchedule(title: clean(title), request: clean(request), date: date, recurrence: recurrence)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
