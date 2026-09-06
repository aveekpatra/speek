import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
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
    /// FIFO the waiting hook reads; the answer written here goes straight back to the agent.
    let replyPath: String?
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
        let reply = items["reply"] ?? ""
        replyPath = reply.isEmpty ? nil : reply
    }

    /// True when the hook is waiting for our answer (no terminal typing needed).
    var isAwaitingReply: Bool { replyPath != nil }

    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    /// Current git branch of the working directory, if it is a checkout.
    var branchName: String? {
        GitBranch.name(in: workingDirectory)
    }
}

enum GitBranch {
    static func name(in directory: String) -> String? {
        guard !directory.isEmpty else { return nil }
        var gitPath = URL(fileURLWithPath: directory).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue,
           let pointer = try? String(contentsOf: gitPath, encoding: .utf8),
           pointer.hasPrefix("gitdir: ") {
            let target = pointer.dropFirst("gitdir: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitPath = target.hasPrefix("/") ? URL(fileURLWithPath: target) : URL(fileURLWithPath: directory).appendingPathComponent(target)
        }
        guard let head = try? String(contentsOf: gitPath.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst("ref: refs/heads/".count)) }
        return String(trimmed.prefix(7))
    }
}

/// Receives agent updates and shows the reply panel at the recording pill's spot: a pill
/// per waiting agent session, the selected agent's message, and a reply box. Dictation
/// lands in the box; Return hands the answer back to the waiting hook (no typing into a
/// terminal); Esc dismisses. Options and permission prompts are answered with a click.
@MainActor
final class AgentUpdateCenter: ObservableObject {
    static let shared = AgentUpdateCenter()

    /// Every session that is waiting for an answer, oldest first.
    @Published private(set) var pending: [AgentUpdate] = []
    @Published var selectedID: UUID?
    @Published var draft = ""
    /// Images pasted or dropped into the reply box; sent to the agent as file paths.
    @Published private(set) var attachments: [URL] = []
    @Published private(set) var recordingState: RecordingState = .idle
    /// Bumped whenever the reply box should take keyboard focus again.
    @Published private(set) var focusTick = 0
    /// While set, the panel stays hidden (Hide button / Cmd+H) and comes back by itself.
    private var snoozedUntil: Date?
    private var refitScheduled = false
    static var snoozeDuration: TimeInterval { TimeInterval(SpeekSettings.shared.agentHideSeconds) }
    @Published private(set) var isSending = false

    var current: AgentUpdate? {
        pending.first { $0.id == selectedID } ?? pending.last
    }

    /// Set by the app at launch so the panel can mirror recording state.
    weak var engine: SpeekEngine? {
        didSet {
            stateObserver = engine?.$recordingState
                .receive(on: RunLoop.main)
                .sink { [weak self] state in self?.recordingState = state }
        }
    }
    var recorder: Recorder? { engine?.recorder }

    var isShowingPanel: Bool { !pending.isEmpty }

    private var panel: AgentReplyPanel?
    private var keyMonitor: Any?
    private var stateObserver: AnyCancellable?
    private var visibilityWatchdog: Timer?
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
            // The user answered in the terminal: that session has nothing left to reply to.
            if let existing = pending.first(where: { $0.session == update.session }) {
                release(existing, with: "dismiss")
                remove(existing)
            }
            return
        }
        if case .other = update.kind { return }
        let isSnoozed = snoozedUntil.map { $0 > Date() } ?? false
        var isNewSession = true
        // One entry per session: a newer event for the same session replaces the old one.
        if let index = pending.firstIndex(where: { $0.session == update.session }) {
            let existing = pending[index]
            if existing.isAwaitingReply && !update.isAwaitingReply {
                // A plain notification (idle, permission prompt) about a session whose hook
                // is already waiting on us: keep the waiting entry. Replacing it would
                // answer that hook with "dismiss", and it must not undo a Hide either.
                if !isSnoozed { showPanel() }
                return
            }
            release(existing, with: "dismiss")
            pending[index] = update
            isNewSession = false
        } else {
            pending.append(update)
        }
        if selectedID == nil || pending.count == 1 || pending.first(where: { $0.id == selectedID }) == nil {
            selectedID = update.id
        }
        // Hide keeps the panel away for the chosen time; only something new (another
        // session, a question, a permission) is worth interrupting that for.
        if !isSnoozed || isNewSession || update.kind == .permission || update.kind == .question {
            showPanel()
        }
        if SpeekSettings.shared.agentSound && SpeekSettings.shared.soundEffects != .off {
            NSSound(named: "Tink")?.play()
        }
    }

    func select(_ update: AgentUpdate) {
        selectedID = update.id
        refit()
    }

    // MARK: Replying

    /// Dictation finished while the panel is up: put the text in the reply box.
    func insertTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = draft.isEmpty ? trimmed : draft + " " + trimmed
        panel?.makeKeyAndOrderFront(nil)
        focusTick += 1
        if SpeekSettings.shared.agentAutoSend { send() }
    }

    static let attachmentsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Speek/agent-attachments", isDirectory: true)

    /// Saves images from the pasteboard (paste) or a drop and lists them under the reply box.
    @discardableResult
    func addImages(from pasteboard: NSPasteboard) -> Bool {
        var images: [NSImage] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL] {
            for url in urls { if let image = NSImage(contentsOf: url) { images.append(image) } }
        }
        if images.isEmpty, let pasted = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            images = pasted
        }
        guard !images.isEmpty else { return false }
        for image in images { if let url = save(image) { attachments.append(url) } }
        refit()
        return true
    }

    func removeAttachment(_ url: URL) {
        attachments.removeAll { $0 == url }
        try? FileManager.default.removeItem(at: url)
        refit()
    }

    private func save(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let directory = Self.attachmentsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("image-\(stamp)-\(Int.random(in: 100...999)).png")
        do { try png.write(to: url) } catch { return nil }
        return url
    }

    /// Reply text plus a list of attached image paths the agent can open.
    private func outgoingText() -> String {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !attachments.isEmpty {
            let list = attachments.map { "- \($0.path)" }.joined(separator: "\n")
            text += (text.isEmpty ? "" : "\n\n") + "Attached image\(attachments.count == 1 ? "" : "s") (open with the Read tool):\n" + list
        }
        return text
    }

    /// Sends the reply box to the selected agent. With a waiting hook the text goes back as
    /// hook output; otherwise (plain notifications) it is pasted into the agent's terminal.
    func send() {
        guard let update = current, !isSending else { return }
        let text = outgoingText()
        guard !text.isEmpty else { return }
        isSending = true
        if update.isAwaitingReply {
            release(update, with: "reply:" + Data(text.utf8).base64EncodedString())
            isSending = false
            clearDraft()
            remove(update)
            return
        }
        Task { @MainActor in
            hidePanel()
            activateTerminal(for: update)
            try? await Task.sleep(nanoseconds: 450_000_000)
            let result = await CursorPaster.forcePasteAtCursor(text)
            if result.didPostPasteCommand {
                try? await Task.sleep(nanoseconds: 300_000_000)
                CursorPaster.performAutoSend(.enter)
            }
            isSending = false
            clearDraft()
            remove(update)
        }
    }

    /// Picks a numbered choice (AskUserQuestion).
    func choose(number: Int) {
        guard let update = current, !isSending else { return }
        let label = update.options.indices.contains(number - 1) ? update.options[number - 1] : String(number)
        if update.isAwaitingReply {
            release(update, with: "option:" + Data(label.utf8).base64EncodedString())
            remove(update)
            return
        }
        isSending = true
        Task { @MainActor in
            hidePanel()
            activateTerminal(for: update)
            try? await Task.sleep(nanoseconds: 450_000_000)
            Keystrokes.type(String(number))
            try? await Task.sleep(nanoseconds: 150_000_000)
            CursorPaster.performAutoSend(.enter)
            isSending = false
            remove(update)
        }
    }

    func allowPermission() {
        guard let update = current, !isSending else { return }
        if update.isAwaitingReply {
            release(update, with: "allow")
            remove(update)
        } else {
            choose(number: 1)
        }
    }

    func denyPermission() {
        guard let update = current, !isSending else { return }
        if update.isAwaitingReply {
            release(update, with: "deny")
            remove(update)
            return
        }
        isSending = true
        Task { @MainActor in
            hidePanel()
            activateTerminal(for: update)
            try? await Task.sleep(nanoseconds: 450_000_000)
            Keystrokes.press(virtualKey: 0x35)   // esc
            isSending = false
            remove(update)
        }
    }

    func replyByVoice() {
        NotificationCenter.default.post(name: .toggleRecorderPanel, object: nil)
    }

    func openTerminal() {
        guard let update = current else { return }
        activateTerminal(for: update)
    }

    func activateTerminal(for update: AgentUpdate) {
        if let bundleID = update.terminalBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            logger.error("No terminal app recorded for \(update.agent.displayName, privacy: .public); reply may land in the wrong window")
        }
    }

    /// Dismiss the selected session without answering: its hook is released so the agent
    /// stops normally. Other waiting sessions stay.
    func dismiss() {
        guard let update = current else { hidePanel(); return }
        release(update, with: "dismiss")
        remove(update)
    }

    /// Answers the waiting hook. Opening a FIFO for writing blocks until the reader is
    /// there, so this runs off the main thread.
    private func release(_ update: AgentUpdate, with line: String) {
        guard let path = update.replyPath else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let fd = open(path, O_WRONLY | O_NONBLOCK)
            guard fd >= 0 else { return }
            var payload = line + "\n"
            payload.withUTF8 { buffer in _ = write(fd, buffer.baseAddress, buffer.count) }
            close(fd)
        }
    }

    private func clearDraft() {
        draft = ""
        attachments = []
    }

    /// Drops a session from the panel; selects the next one or hides the panel.
    private func remove(_ update: AgentUpdate) {
        pending.removeAll { $0.id == update.id }
        if pending.isEmpty {
            selectedID = nil
            clearDraft()
            hidePanel()
        } else {
            if selectedID == update.id { selectedID = pending.last?.id }
            refit()
        }
    }

    // MARK: Panel

    static let panelWidth: CGFloat = 600
    /// Transparent margin around the glass cards so their soft shadow is not cut off by
    /// the window edge. PanelAnchor pulls the window back by the same amount.
    static let contentMargin: CGFloat = 28

    private func showPanel() {
        if panel == nil {
            let panel = AgentReplyPanel(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 300))
            let host = NSHostingView(rootView: AgentReplyView(center: self))
            // Never let SwiftUI size the window; PanelAnchor owns the frame.
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            self.panel = panel
        }
        if keyMonitor == nil {
            // Cmd+H anywhere in Speek while the panel is up hides the panel, not the app:
            // with the main window focused it would otherwise reach "Hide Speek", which
            // hides every window without arming the snooze, and the watchdog would bring
            // the panel straight back.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.panel?.isVisible == true,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "h" else { return event }
                self.snooze()
                return nil
            }
        }
        guard let panel else { return }
        let size = fittedSize(of: panel)
        let position = PanelPosition.current
        panel.apply {
            if panel.isVisible {
                // Already up (new event, or brought back): grow in place, anchor locked.
                panel.setFrame(PanelAnchor.resized(panel.frame, to: size, position: position, on: panel.screen), display: true)
            } else if let screen = PanelAnchor.screen {
                panel.setFrame(PanelAnchor.frame(for: size, position: position, on: screen, contentInset: Self.contentMargin), display: false)
            }
        }
        snoozedUntil = nil
        panel.makeKeyAndOrderFront(nil)
        focusTick += 1
        startVisibilityWatchdog()
    }

    private func fittedSize(of panel: NSPanel) -> NSSize {
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.contentView?.fittingSize ?? panel.frame.size
        size.width = Self.panelWidth + Self.contentMargin * 2
        return size
    }

    /// While any session is waiting, the panel must stay on screen. If anything hides it
    /// (a Space switch, a screen change, an app going full screen), bring it back.
    private func startVisibilityWatchdog() {
        guard visibilityWatchdog == nil else { return }
        visibilityWatchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.pending.isEmpty else {
                    self.visibilityWatchdog?.invalidate()
                    self.visibilityWatchdog = nil
                    return
                }
                if let until = self.snoozedUntil, until > Date() { return }
                // The user hid the whole app (Hide Speek / Cmd+Option+H elsewhere): the
                // panel comes back when Speek is unhidden, not before.
                if NSApp.isHidden { return }
                if let panel = self.panel, !panel.isVisible {
                    self.logger.notice("Agent panel was hidden with \(self.pending.count) waiting; showing it again")
                    panel.orderFrontRegardless()
                } else if let panel = self.panel, !panel.isOnActiveSpace {
                    panel.orderFrontRegardless()
                }
            }
        }
    }

    /// Menu bar / pill entry point: bring the panel forward for the waiting sessions.
    func showPendingPanel() {
        guard !pending.isEmpty else { return }
        showPanel()
    }

    /// Gets the panel out of the way for a moment without answering anything. It
    /// returns on its own after the Hide duration set under Agent Panel, on the next
    /// agent event, or from the menu bar.
    func snooze() {
        guard panel?.isVisible == true else { return }
        let duration = Self.snoozeDuration
        let until = Date().addingTimeInterval(duration)
        snoozedUntil = until
        hidePanel()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.snoozedUntil == until, !self.pending.isEmpty else { return }
            self.showPanel()
        }
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        if panel.isKeyWindow { panel.resignKey() }
        panel.orderOut(nil)
    }

    /// Re-fits the panel height after content changes (longer draft, other session,
    /// attachments). Runs on the next run loop turn: it is triggered from inside a
    /// SwiftUI update, where the hosting view's fitting size is not settled yet (it can
    /// even report zero). The anchored edge stays where it is: bottom placement grows
    /// upward, top placement downward, side placements stay centred.
    fileprivate func refit() {
        guard !refitScheduled else { return }
        refitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refitScheduled = false
            guard let panel = self.panel, panel.isVisible else { return }
            let size = self.fittedSize(of: panel)
            guard size.height >= Self.contentMargin * 2 + 80, size != panel.frame.size else { return }
            panel.apply {
                panel.setFrame(PanelAnchor.resized(panel.frame, to: size, position: PanelPosition.current, on: panel.screen), display: true, animate: false)
            }
        }
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
        // Always centred on its anchor; a drag inside the reply box selects text.
        isMovable = false
        isMovableByWindowBackground = false
    }

    override func cancelOperation(_ sender: Any?) {
        AgentUpdateCenter.shared.dismiss()
    }

    /// PanelAnchor places the window exactly; the transparent shadow margin may overlap
    /// the menu bar or screen edge, so AppKit must not nudge it back inside.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // MARK: Frame lock
    // NSHostingView resizes its window on its own when the SwiftUI content changes
    // (windowDidLayout -> updateAnimatedWindowSize), anchoring wherever it likes; a
    // shrinking reply box could push the whole panel off screen. Only frames set through
    // `apply` (PanelAnchor placement and refit) are accepted.

    private var allowsFrameChange = false

    func apply(_ change: () -> Void) {
        allowsFrameChange = true
        change()
        allowsFrameChange = false
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard allowsFrameChange || !isVisible else { return }
        super.setFrame(frameRect, display: flag)
    }


    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        guard allowsFrameChange || !isVisible else { return }
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }

    override func setContentSize(_ size: NSSize) {
        guard allowsFrameChange || !isVisible else { return }
        super.setContentSize(size)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        guard allowsFrameChange || !isVisible else { return }
        super.setFrameOrigin(point)
    }

    /// Cmd+V with an image on the clipboard attaches it; text pastes fall through to the
    /// field. Cmd+H hides the panel for a moment.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            AgentUpdateCenter.shared.snooze()
            return
        }
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            let pasteboard = NSPasteboard.general
            let hasText = pasteboard.string(forType: .string) != nil
            if !hasText, AgentUpdateCenter.shared.addImages(from: pasteboard) { return }
        }
        super.sendEvent(event)
    }
}

/// Synthesised keystrokes for answering terminal prompts (legacy, non-waiting hooks).
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

/// Three stacked glass pieces: session pills, the agent's message, the reply box.
private struct AgentReplyView: View {
    @ObservedObject var center: AgentUpdateCenter
    @ObservedObject private var modeManager = ModeManager.shared
    @State private var replyFocused = false
    @State private var appeared = false

    private let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private let glassTint = Color.black.opacity(0.55)

    var body: some View {
        Group {
            if let update = center.current {
                VStack(alignment: .leading, spacing: 12) {
                    sessionPills
                    messageCard(update)
                    if !update.options.isEmpty { optionRow(update) }
                    if update.kind == .permission { permissionRow }
                    replyCard(update)
                }
                .frame(width: AgentUpdateCenter.panelWidth)
                .padding(AgentUpdateCenter.contentMargin)
                .scaleEffect(appeared ? 1 : 0.94, anchor: .bottom)
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { appeared = true }
                }
                .onDisappear { appeared = false }
                .onChange(of: center.draft) { _, _ in center.refit() }
                .onChange(of: center.selectedID) { _, _ in center.refit() }
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .colorScheme(.dark)
    }

    // MARK: Pills

    private var sessionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(center.pending) { update in
                    let isSelected = update.id == center.current?.id
                    // Same material and properties as the message and reply cards; a plain
                    // tap target instead of a Button so nothing restyles it when the panel
                    // is not the key window.
                    HStack(spacing: 8) {
                        update.agent.icon.frame(width: 18, height: 18)
                        Text(pillTitle(update))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.6))
                            .lineLimit(1)
                        if update.kind != .finished {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 14)
                    .frame(height: 38)
                    .glassEffect(.regular.tint(glassTint), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(isSelected ? 0.18 : 0.1), lineWidth: 0.8))
                    .contentShape(Capsule())
                    .onTapGesture { center.select(update) }
                    .help("\(update.agent.displayName) \(update.kind.title) in \(update.workingDirectory)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func pillTitle(_ update: AgentUpdate) -> String {
        let project = update.projectName.isEmpty ? update.agent.displayName : update.projectName
        if let branch = update.branchName, !branch.isEmpty { return "\(project) • \(branch)" }
        return project
    }

    // MARK: Message

    private func messageCard(_ update: AgentUpdate) -> some View {
        ScrollView {
            if update.message.isEmpty {
                Text("\(update.agent.displayName) \(update.kind.title).")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownContentView(update.message, fontSize: 15, foregroundColor: .white.opacity(0.94))
            }
        }
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(glassTint), in: cardShape)
        .overlay(cardShape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8))
    }

    private func optionRow(_ update: AgentUpdate) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(update.options.enumerated()), id: \.offset) { index, label in
                Button { center.choose(number: index + 1) } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                        Text(label).font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 8) {
            Button("Allow") { center.allowPermission() }
                .buttonStyle(.glassProminent)
                .tint(Color.accentColor)
            Button("Deny") { center.denyPermission() }
                .buttonStyle(.glass)
            Spacer()
        }
    }

    // MARK: Reply

    private func replyCard(_ update: AgentUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ReplyEditor(
                text: $center.draft,
                isFocused: $replyFocused,
                focusTick: center.focusTick,
                onSend: { center.send() },
                onEscape: { center.dismiss() }
            )
            .overlay(alignment: .topLeading) {
                if center.draft.isEmpty {
                    Text("Type or dictate what you want changed.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.4))
                        .allowsHitTesting(false)
                }
            }
            if !center.attachments.isEmpty { attachmentStrip }
            HStack(spacing: 14) {
                voiceStatus
                Spacer()
                Button { center.snooze() } label: {
                    HStack(spacing: 8) {
                        Text("Hide")
                        SpeekKeycapRow(keys: ["⌘", "H"])
                    }
                }
                .buttonStyle(.plain)
                .help("Hide the panel for \(Int(AgentUpdateCenter.snoozeDuration)) seconds. It comes back by itself, on the next agent event, or from the menu bar.")
                Button { center.dismiss() } label: {
                    HStack(spacing: 8) {
                        Text("Dismiss")
                        SpeekKeycapRow(keys: ["esc"])
                    }
                }
                .buttonStyle(.plain)
                Button { center.send() } label: {
                    HStack(spacing: 8) {
                        Text("Send")
                        SpeekKeycapRow(keys: ["⏎"])
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
            }
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .glassEffect(.regular.tint(glassTint), in: cardShape)
        .overlay(cardShape.strokeBorder(replyFocused ? Color.white.opacity(0.16) : Color.white.opacity(0.1), lineWidth: 0.8))
        .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: nil) { providers in
            let pasteboard = NSPasteboard(name: .init("com.aveekpatra.speek.drop"))
            var accepted = false
            for provider in providers {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in
                        pasteboard.clearContents()
                        pasteboard.writeObjects([image])
                        _ = center.addImages(from: pasteboard)
                    }
                }
                accepted = true
            }
            return accepted
        }
    }

    private var canSend: Bool {
        (!center.draft.trimmingCharacters(in: .whitespaces).isEmpty || !center.attachments.isEmpty) && !center.isSending
    }

    @ViewBuilder
    private var voiceStatus: some View {
        switch center.recordingState {
        case .recording:
            HStack(spacing: 10) {
                if let recorder = center.recorder { AgentListeningBars(recorder: recorder) }
                Text("Listening...")
            }
        case .transcribing, .enhancing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text(center.recordingState == .enhancing ? "Rewriting..." : "Transcribing...")
            }
        default:
            Button { center.replyByVoice() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .medium))
                    Text(modeManager.currentEffectiveConfiguration?.name ?? "Voice to text")
                }
            }
            .buttonStyle(.plain)
            .help("Start dictating (\((ShortcutStore.shortcut(for: .primaryRecording)?.displayTokens ?? []).joined(separator: " ")))")
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(center.attachments, id: \.self) { url in
                    ZStack(alignment: .topTrailing) {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
                        }
                        Button { center.removeAttachment(url) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white, Color.black.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Editable, selectable reply box backed by NSTextView: the SwiftUI TextField does not
/// reliably take keyboard focus inside a non-activating panel, and a text view gives
/// proper selection, arrow keys and paste. Return sends, Shift+Return breaks a line,
/// Escape dismisses. Dictation appends at the end (see AgentUpdateCenter.insertTranscript).
private struct ReplyEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusTick: Int
    let onSend: () -> Void
    let onEscape: () -> Void

    static let font = NSFont.systemFont(ofSize: 17)
    static let minHeight: CGFloat = 48
    static let maxHeight: CGFloat = 8 * 22

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ReplyTextView {
        let view = ReplyTextView()
        view.delegate = context.coordinator
        view.font = Self.font
        view.textColor = .white
        view.insertionPointColor = .white
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.25)]
        view.onSend = onSend
        view.onEscape = onEscape
        view.onFocusChange = { focused in Task { @MainActor in context.coordinator.parent.isFocused = focused } }
        view.string = text
        return view
    }

    func updateNSView(_ view: ReplyTextView, context: Context) {
        context.coordinator.parent = self
        view.onSend = onSend
        view.onEscape = onEscape
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ReplyTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? view.bounds.width
        guard width > 0, let container = view.textContainer, let layout = view.layoutManager else {
            return CGSize(width: proposal.width ?? 0, height: Self.minHeight)
        }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        return CGSize(width: width, height: min(max(used, Self.minHeight), Self.maxHeight))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReplyEditor
        var lastFocusTick = -1
        init(_ parent: ReplyEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

private final class ReplyTextView: NSTextView {
    var onSend: (() -> Void)?
    var onEscape: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                super.insertNewline(nil)
            } else {
                onSend?()
            }
        case #selector(cancelOperation(_:)):
            onEscape?()
        default:
            super.doCommand(by: selector)
        }
    }
}

private struct AgentListeningBars: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        LiveBarsView(audioMeter: recorder.audioMeter, isActive: true, barCount: 9, maxHeight: 16)
            .frame(height: 22)
    }
}
