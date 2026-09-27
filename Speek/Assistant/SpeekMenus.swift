import SwiftUI
import AppKit


/// What Speek is doing right now, shared by the status item icon and both menus.
@MainActor
private struct SpeekActivity {
    let recording: Bool
    let transcribing: Bool
    let agentsWaiting: Int
    let dueReviews: Int
    let permissionPending: Bool
    let backgroundTasks: Int

    init(_ assistant: AssistantController, _ agents: AgentUpdateCenter, _ scheduler: TaskScheduler, _ computer: ComputerTaskManager, _ cua: CodexComputerUse) {
        recording = assistant.recording
        transcribing = assistant.busy && assistant.phase == "Transcribing"
        agentsWaiting = agents.pending.count
        dueReviews = scheduler.jobs.filter { $0.status == .awaitingReview }.count
        permissionPending = cua.approval != nil
        backgroundTasks = computer.jobs.filter { $0.status == .queued || $0.status == .running }.count
    }

    var needsAttention: Bool { agentsWaiting > 0 || dueReviews > 0 || permissionPending }

    var status: String {
        if recording { return "Listening" }
        if transcribing { return "Transcribing" }
        if permissionPending { return "A task needs your permission" }
        if agentsWaiting > 0 { return agentsWaiting == 1 ? "A coding assistant is waiting" : "\(agentsWaiting) coding assistants are waiting" }
        if dueReviews > 0 { return dueReviews == 1 ? "A scheduled request is ready" : "\(dueReviews) scheduled requests are ready" }
        if backgroundTasks > 0 { return backgroundTasks == 1 ? "1 task running" : "\(backgroundTasks) tasks running" }
        return "Ready"
    }
}

// MARK: Status item (right side of the menu bar)

/// Idle, listening, or needs attention. The menu explains which.
struct StatusItemIcon: View {
    @ObservedObject private var assistant = AssistantController.shared
    @ObservedObject private var agents = AgentUpdateCenter.shared
    @ObservedObject private var scheduler = TaskScheduler.shared
    @ObservedObject private var computer = ComputerTaskManager.shared
    @ObservedObject private var cua = CodexComputerUse.shared

    var body: some View {
        let activity = SpeekActivity(assistant, agents, scheduler, computer, cua)
        Image(systemName: activity.recording ? "waveform.circle.fill" : activity.needsAttention ? "waveform.badge.exclamationmark" : "waveform")
            .accessibilityLabel("Speek, " + activity.status)
    }
}

/// Quick actions first, then anything waiting for you, then the app.
struct StatusMenuContent: View {
    @ObservedObject var updater: UpdaterViewModel
    @ObservedObject private var assistant = AssistantController.shared
    @ObservedObject private var agents = AgentUpdateCenter.shared
    @ObservedObject private var scheduler = TaskScheduler.shared
    @ObservedObject private var computer = ComputerTaskManager.shared
    @ObservedObject private var cua = CodexComputerUse.shared

    var body: some View {
        let activity = SpeekActivity(assistant, agents, scheduler, computer, cua)
        Text("Speek: " + activity.status)
        Divider()
        Button(assistant.recording ? "Stop Speaking" : "Speak") { assistant.toggleVoice() }
            .disabled(assistant.busy && !assistant.recording)
        Button("Type a Request...") { assistant.show(typing: true) }
        Button("Circle Screen Context") { assistant.circleContext() }
            .disabled(assistant.busy || assistant.recording)
        Button("Mark Up Screen") { assistant.markUpScreen() }
            .disabled(assistant.busy || assistant.recording)
        Divider()
        RecentDictationsMenu()
        Button("Copy Last Dictation") { copyLastDictation() }
            .disabled(DictationHistory.shared.entries.isEmpty)
        if activity.needsAttention || activity.backgroundTasks > 0 {
            Divider()
            if activity.permissionPending { Button("Review Permission...") { SpeekMainWindow.shared.show() } }
            if activity.agentsWaiting > 0 { Button("Reply to Coding Assistant...") { agents.showPendingPanel() } }
            ForEach(scheduler.jobs.filter { $0.status == .awaitingReview }.prefix(3)) { job in
                Button("Review \"" + job.title + "\"") { _ = scheduler.reviewJob(job.id) }
            }
            if activity.backgroundTasks > 0 { Button("Stop Background Tasks") { assistant.stopFileTask() } }
        }
        Divider()
        Button("Open Speek") { SpeekMainWindow.shared.show() }
        Button("Dictation History...") { SpeekMainWindow.shared.showDictationHistory() }
        Button("Settings...") { SpeekMainWindow.shared.showSettings() }
        Divider()
        CheckForUpdatesView(updaterViewModel: updater)
        Button("Quit Speek") { NSApp.terminate(nil) }
    }
}

@MainActor
func copyLastDictation() {
    guard let last = DictationHistory.shared.entries.max(by: { $0.date < $1.date }) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(last.text, forType: .string)
}

// MARK: Main menu (Speek, File, Edit, View, Voice, Window, Help)

struct SpeekCommands: Commands {
    @ObservedObject var updater: UpdaterViewModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updaterViewModel: updater)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") { SpeekMainWindow.shared.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Task") { SpeekMainWindow.shared.requestNewTask() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Schedule...") { SpeekMainWindow.shared.requestNewSchedule() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .textEditing) {
            Button("Find Chats...") { SpeekMainWindow.shared.requestFindChats() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        CommandGroup(before: .toolbar) {
            Button("Tasks") { SpeekMainWindow.shared.showSection(.tasks) }.keyboardShortcut("1", modifiers: .command)
            Button("Memory") { SpeekMainWindow.shared.showSection(.memory) }.keyboardShortcut("2", modifiers: .command)
            Button("Models & Voice") { SpeekMainWindow.shared.showSection(.connections) }.keyboardShortcut("3", modifiers: .command)
            Button("Integrations") { SpeekMainWindow.shared.showSection(.integrations) }.keyboardShortcut("4", modifiers: .command)
            Divider()
            Button("Dictation History") { SpeekMainWindow.shared.showDictationHistory() }.keyboardShortcut("y", modifiers: .command)
            Divider()
        }
        CommandMenu("Voice") { VoiceMenuItems() }
        CommandGroup(replacing: .help) {
            Button("Speek Help") { NSWorkspace.shared.open(SpeekLinks.repository) }
            Button("Release Notes") { NSWorkspace.shared.open(SpeekLinks.releases) }
            Divider()
            Button("Report an Issue...") { NSWorkspace.shared.open(SpeekLinks.issues) }
        }
    }
}

private struct VoiceMenuItems: View {
    @ObservedObject private var assistant = AssistantController.shared
    @ObservedObject private var agents = AgentUpdateCenter.shared

    var body: some View {
        Button(assistant.recording ? "Stop Speaking" : "Speak") { assistant.toggleVoice() }
            .disabled(assistant.busy && !assistant.recording)
        Button("Type a Request...") { assistant.show(typing: true) }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        Button("Circle Screen Context") { assistant.circleContext() }
            .disabled(assistant.busy || assistant.recording)
        Button("Mark Up Screen") { assistant.markUpScreen() }
            .disabled(assistant.busy || assistant.recording)
        Divider()
        RecentDictationsMenu()
        Button("Copy Last Dictation") { copyLastDictation() }
            .keyboardShortcut("c", modifiers: [.command, .option])
        Divider()
        Button("Reply to Coding Assistant...") { agents.showPendingPanel() }
            .disabled(agents.pending.isEmpty)
        Button("Stop Background Tasks") { assistant.stopFileTask() }
            .disabled(!assistant.fileTaskRunning)
    }
}
