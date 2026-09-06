import SwiftUI
import AppKit
import Combine
import os

/// One event forwarded by the agent hook through `speek://agent-update`.
struct AgentUpdate: Identifiable, Equatable {
    enum Kind: Equatable {
        case finished
        case permission
        case question
        case waiting
        case promptSubmitted
        case other(String)

        var title: String {
            switch self {
            case .finished: return "finished"
            case .permission: return "needs permission"
            case .question: return "has a question"
            case .waiting: return "is waiting for you"
            case .promptSubmitted: return "received your prompt"
            case .other(let name): return name
            }
        }
    }

    let id = UUID()
    let agent: AgentPlugin
    let kind: Kind
    let message: String
    /// AskUserQuestion choices (labels), in order.
    let options: [String]
    let session: String
    let workingDirectory: String
    let terminalBundleID: String?
    let receivedAt = Date()

    init?(url: URL) {
        guard url.scheme == "speek", url.host == "agent-update",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        agent = items["agent"] == "codex" ? .codex : .claudeCode
        let event = items["event"] ?? ""
        let notification = items["notification"] ?? ""
        switch event {
        case "Stop", "agent-turn-complete": kind = .finished
        case "PermissionRequest": kind = .permission
        case "PreToolUse": kind = .question
        case "UserPromptSubmit": kind = .promptSubmitted
        case "Notification":
            kind = notification.contains("permission") ? .permission : .waiting
        default: kind = .other(event)
        }
        message = (items["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        options = (items["options"] ?? "").split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        session = items["session"] ?? ""
        workingDirectory = items["cwd"] ?? ""
        let app = items["app"] ?? ""
        terminalBundleID = app.isEmpty ? nil : app
    }

    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }
}

/// Receives agent updates and turns the recording pill into a reply panel: the agent's
/// message on top, a reply box below. Dictation lands in the box, Return sends it to the
/// agent's terminal, Esc dismisses. Options and permission prompts are answered with a click.
@MainActor
final class AgentUpdateCenter: ObservableObject {
    static let shared = AgentUpdateCenter()

    @Published private(set) var current: AgentUpdate?
    @Published var draft = ""
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var isSending = false

    /// Set by the app at launch so the panel can mirror recording state.
    weak var engine: SpeekEngine? {
        didSet {
            stateObserver = engine?.$recordingState
                .receive(on: RunLoop.main)
                .sink { [weak self] state in self?.recordingState = state }
        }
    }
    var recorder: Recorder? { engine?.recorder }

    var isShowingPanel: Bool { current != nil }

    private var panel: AgentReplyPanel?
    private var dismissTask: Task<Void, Never>?
    private var stateObserver: AnyCancellable?
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "AgentUpdateCenter")

    private init() {}

    // MARK: URL entry point

    func handle(url: URL) -> Bool {
        guard url.scheme == "speek" else { return false }
        switch url.host {
        case "agent-update":
            guard let update = AgentUpdate(url: url) else { return false }
            receive(update)
            return true
        case "record":
            NotificationCenter.default.post(name: .toggleRecorderPanel, object: nil)
            return true
        case "settings":
            NotificationCenter.default.post(name: .speekNavigate, object: nil, userInfo: ["page": SpeekPage.configuration.rawValue])
            NSApp.activate(ignoringOtherApps: true)
            return true
        default:
            return false
        }
    }

    func receive(_ update: AgentUpdate) {
        logger.notice("Agent update: \(update.agent.displayName, privacy: .public) \(update.kind.title, privacy: .public) session=\(update.session, privacy: .public)")
        if update.kind == .promptSubmitted {
            // The user answered in the terminal: nothing left to reply to.
            if current?.session == update.session || current == nil { dismiss() }
            return
        }
        if case .other = update.kind { return }
        let isNewConversation = current?.session != update.session
        current = update
        if isNewConversation { draft = "" }
        showPanel()
        if SpeekSettings.shared.soundEffects != .off {
            NSSound(named: "Tink")?.play()
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    // MARK: Replying

    /// Dictation finished while the panel is up: put the text in the reply box.
    func insertTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = draft.isEmpty ? trimmed : draft + " " + trimmed
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Sends the reply box to the agent's terminal and presses Return.
    func send() {
        guard let update = current, !isSending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        Task { @MainActor in
            activateTerminal(for: update)
            try? await Task.sleep(nanoseconds: 350_000_000)
            let result = await CursorPaster.pasteAtCursorAndWaitUntilPosted(text)
            if result.didPostPasteCommand {
                try? await Task.sleep(nanoseconds: 250_000_000)
                CursorPaster.performAutoSend(.enter)
            }
            isSending = false
            draft = ""
            dismiss()
        }
    }

    /// Picks a numbered choice in the agent's terminal (AskUserQuestion / permission list).
    func choose(number: Int) {
        guard let update = current, !isSending else { return }
        isSending = true
        Task { @MainActor in
            activateTerminal(for: update)
            try? await Task.sleep(nanoseconds: 350_000_000)
            Keystrokes.type(String(number))
            try? await Task.sleep(nanoseconds: 150_000_000)
            CursorPaster.performAutoSend(.enter)
            isSending = false
            dismiss()
        }
    }

    func allowPermission() { choose(number: 1) }

    func denyPermission() {
        guard let update = current, !isSending else { return }
        isSending = true
        Task { @MainActor in
            activateTerminal(for: update)
            try? await Task.sleep(nanoseconds: 350_000_000)
            Keystrokes.press(virtualKey: 0x35)   // esc
            isSending = false
            dismiss()
        }
    }

    func replyByVoice() {
        NotificationCenter.default.post(name: .toggleRecorderPanel, object: nil)
    }

    func openTerminal() {
        guard let update = current else { return }
        activateTerminal(for: update)
        dismiss()
    }

    func activateTerminal(for update: AgentUpdate) {
        if let bundleID = update.terminalBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        panel?.orderOut(nil)
    }

    // MARK: Panel

    private func showPanel() {
        if panel == nil {
            let panel = AgentReplyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 240))
            panel.contentView = NSHostingView(rootView: AgentReplyView(center: self))
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.contentView?.fittingSize ?? panel.frame.size
        size.width = 520
        panel.setContentSize(size)
        // Same spot as the recording pill: bottom center, or the always-show edge.
        let frame = screen.visibleFrame
        let settings = SpeekSettings.shared
        let origin: NSPoint
        if settings.keepsRecorderVisibleWhenIdle && settings.alwaysShowEdge == .top {
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 10)
        } else {
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 26)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Re-fits the panel height after content changes (longer draft, more options).
    fileprivate func refit() {
        guard let panel, panel.isVisible else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.contentView?.fittingSize ?? panel.frame.size
        size.width = 520
        let bottomAligned = !(SpeekSettings.shared.keepsRecorderVisibleWhenIdle && SpeekSettings.shared.alwaysShowEdge == .top)
        var frame = panel.frame
        if bottomAligned { frame.origin.y = frame.maxY - size.height }
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }
}

/// Floating, non-activating panel that can still take key focus for typing a reply.
final class AgentReplyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    override func cancelOperation(_ sender: Any?) {
        AgentUpdateCenter.shared.dismiss()
    }
}

/// Synthesised keystrokes for answering terminal prompts.
enum Keystrokes {
    static func type(_ text: String) {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        for scalar in text.utf16 {
            var unit = scalar
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func press(virtualKey: CGKeyCode) {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)?.post(tap: .cghidEventTap)
    }
}

// MARK: - Panel view

private struct AgentReplyView: View {
    @ObservedObject var center: AgentUpdateCenter
    @FocusState private var replyFocused: Bool
    @State private var appeared = false

    private var shortcutTokens: [String] {
        ShortcutStore.shortcut(for: .primaryRecording)?.displayTokens ?? ["⌘"]
    }

    var body: some View {
        Group {
            if let update = center.current {
                VStack(alignment: .leading, spacing: 12) {
                    header(update)
                    if !update.message.isEmpty {
                        ScrollView {
                            Text(update.message)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.92))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 190)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if !update.options.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(Array(update.options.enumerated()), id: \.offset) { index, label in
                                Button {
                                    center.choose(number: index + 1)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(Color.white.opacity(0.14)))
                                        Text(label).font(.system(size: 13))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if update.kind == .permission {
                        HStack(spacing: 8) {
                            Button("Allow") { center.allowPermission() }
                                .buttonStyle(.glassProminent)
                                .tint(Color.accentColor)
                            Button("Deny") { center.denyPermission() }
                                .buttonStyle(.glass)
                            Spacer()
                        }
                    }
                    replyBox(update)
                    footer
                }
                .padding(16)
                .frame(width: 520)
                .glassEffect(.regular.tint(Color.black.opacity(0.62)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                )
                .scaleEffect(appeared ? 1 : 0.9, anchor: .bottom)
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { appeared = true }
                    replyFocused = true
                }
                .onDisappear { appeared = false }
                .onChange(of: center.draft) { _, _ in center.refit() }
                .onChange(of: center.current?.id) { _, _ in
                    center.refit()
                    replyFocused = true
                }
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .colorScheme(.dark)
    }

    private func header(_ update: AgentUpdate) -> some View {
        HStack(spacing: 10) {
            update.agent.icon.frame(width: 22, height: 22)
            Text(update.agent.displayName)
                .font(.system(size: 14, weight: .semibold))
            Text(update.kind.title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            if !update.projectName.isEmpty {
                Text(update.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            Spacer()
            Button { center.openTerminal() } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Open the terminal")
            Button { center.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Dismiss (esc)")
        }
    }

    private func replyBox(_ update: AgentUpdate) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if center.recordingState == .recording {
                HStack(spacing: 10) {
                    if let recorder = center.recorder {
                        AgentListeningBars(recorder: recorder)
                    }
                    Text("Listening...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                .frame(minHeight: 22)
            } else if center.recordingState == .transcribing || center.recordingState == .enhancing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(center.recordingState == .enhancing ? "Rewriting..." : "Transcribing...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                .frame(minHeight: 22)
            } else {
                TextField("Reply to \(update.agent.displayName)...", text: $center.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...6)
                    .focused($replyFocused)
                    .onSubmit { center.send() }
            }
            Button { center.send() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(center.draft.isEmpty ? Color.white.opacity(0.15) : Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(center.draft.trimmingCharacters(in: .whitespaces).isEmpty || center.isSending)
            .help("Send (Return)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(replyFocused ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            SpeekKeycapRow(keys: shortcutTokens)
            Text("to speak")
            Text("·").foregroundStyle(.white.opacity(0.3))
            SpeekKeycapRow(keys: ["⏎"])
            Text("to send")
            Text("·").foregroundStyle(.white.opacity(0.3))
            SpeekKeycapRow(keys: ["esc"])
            Text("to dismiss")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.55))
    }
}

private struct AgentListeningBars: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        LiveBarsView(audioMeter: recorder.audioMeter, isActive: true, barCount: 9, maxHeight: 16)
    }
}
