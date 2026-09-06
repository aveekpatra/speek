import SwiftUI
import AppKit
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
        session = items["session"] ?? ""
        workingDirectory = items["cwd"] ?? ""
        let app = items["app"] ?? ""
        terminalBundleID = app.isEmpty ? nil : app
    }

    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }
}

/// Receives agent updates, shows the overlay, and remembers where the next dictation
/// should be delivered.
@MainActor
final class AgentUpdateCenter: ObservableObject {
    static let shared = AgentUpdateCenter()

    @Published private(set) var current: AgentUpdate?
    /// Set while an agent is waiting; the next dictation is pasted into its terminal.
    private(set) var replyTarget: AgentUpdate?

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "AgentUpdateCenter")

    private init() {}

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
        current = update
        replyTarget = update
        showPanel()
        if SpeekSettings.shared.soundEffects != .off {
            NSSound(named: "Tink")?.play()
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Called by the delivery pipeline: returns and clears the pending reply target.
    func consumeReplyTarget() -> AgentUpdate? {
        defer { replyTarget = nil; dismiss() }
        return replyTarget
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
        replyTarget = nil
        panel?.orderOut(nil)
    }

    // MARK: Panel

    private func showPanel() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: AgentOverlayView(center: self))
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        if let hosting = panel.contentView as? NSHostingView<AgentOverlayView> {
            hosting.rootView = AgentOverlayView(center: self)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.contentView?.fittingSize ?? panel.frame.size
        size.width = 404
        panel.setContentSize(size)
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 12, y: screen.visibleFrame.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }
}

// MARK: - Overlay view

private struct AgentOverlayView: View {
    @ObservedObject var center: AgentUpdateCenter

    var body: some View {
        Group {
            if let update = center.current {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        update.agent.icon.frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(update.agent.displayName) \(update.kind.title)")
                                .font(.system(size: 14, weight: .semibold))
                            if !update.projectName.isEmpty {
                                Text(update.projectName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { center.dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if !update.message.isEmpty {
                        Text(update.message)
                            .font(.system(size: 13))
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Button {
                            center.replyByVoice()
                        } label: {
                            Label("Reply by voice", systemImage: "mic.fill")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.accentColor)
                        Button("Open terminal") { center.openTerminal() }
                            .buttonStyle(.glass)
                            .foregroundStyle(.primary)
                        Spacer()
                        SpeekKeycapRow(keys: ShortcutStore.shortcut(for: .primaryRecording)?.displayTokens ?? [])
                    }
                }
                .padding(16)
                .frame(width: 380)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(12)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }
}
