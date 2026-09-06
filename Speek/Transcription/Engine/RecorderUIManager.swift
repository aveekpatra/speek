import Foundation
import SwiftUI
import os

enum RecorderPanelStyle: String, CaseIterable, Identifiable {
    case notch
    case mini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notch:
            return String(localized: "Notch")
        case .mini:
            return String(localized: "Mini")
        }
    }

    static var stored: RecorderPanelStyle {
        let rawValue = UserDefaults.standard.string(forKey: "RecorderType") ?? RecorderPanelStyle.mini.rawValue
        return RecorderPanelStyle(rawValue: rawValue) ?? .mini
    }
}

@MainActor
protocol RecorderPanelPresenting: AnyObject {
    var isRecorderPanelVisible: Bool { get }
    func dismissRecorderPanel() async
    func dismissRecorderPanelWithPasteHint(text: String) async
}

@MainActor
class RecorderUIManager: ObservableObject, RecorderPanelPresenting {
    @Published var recorderPanelStyle: RecorderPanelStyle = .stored {
        didSet {
            guard oldValue != recorderPanelStyle else { return }
            rebuildVisiblePanel(previousStyle: oldValue)
            UserDefaults.standard.set(recorderPanelStyle.rawValue, forKey: "RecorderType")
        }
    }

    var recorderType: String {
        get { recorderPanelStyle.rawValue }
        set { recorderPanelStyle = RecorderPanelStyle(rawValue: newValue) ?? .mini }
    }

    @Published var isRecorderPanelVisible = false {
        didSet {
            guard oldValue != isRecorderPanelVisible else { return }

            if isRecorderPanelVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }

    private var miniWindowManager: MiniWindowManager?
    private var coachDismissTask: Task<Void, Never>?
    private var pasteHintDismissTask: Task<Void, Never>?

    private weak var engine: SpeekEngine?
    private var recorder: Recorder?

    /// Current engine recording state, for external commit/cancel decisions.
    var currentRecordingState: RecordingState? { engine?.recordingState }

    /// Commit the active recording and auto-send (Enter) after paste.
    func commitWithAutoSend(modeId: UUID? = nil) async {
        engine?.forceAutoSendOnCommit = true
        await toggleRecorderPanel(modeId: modeId)
    }

    /// First Escape: arm/disarm the in-panel "Esc again to cancel" confirm overlay.
    func setCancelConfirming(_ confirming: Bool) {
        engine?.isCancelConfirming = confirming
    }

    /// Second Escape: play the dismiss effect (see DismissEffectStyle) in the panel,
    /// then tear it down.
    func cancelRecordingAnimated() async {
        guard let engine else { return }
        engine.isCancelConfirming = false
        engine.isCanceling = true
        // Let the widget play its chosen dismiss effect (sparkle / vanish / sequential
        // dissolve / content scatter — see Variant2View) before the window is actually
        // torn down.
        let effectDuration: TimeInterval = 0.3
        try? await Task.sleep(nanoseconds: UInt64(effectDuration * 1_000_000_000))
        // Keep isCanceling true through teardown so the pill stays collapsed/faded and
        // doesn't animate back up before the window is hidden. Reset only after the
        // panel is gone so the next spawn starts clean.
        await cancelRecordingAfterEffect()
        engine.isCanceling = false
    }

    /// Same teardown as `cancelRecording()`, used only right after the panel has
    /// already played its own dismiss effect above. Most effects already animate the
    /// shell/panel to invisible themselves by this point, so — unlike the plain
    /// `dismissRecorderPanel()` path, which intentionally keeps MiniWindowManager's own
    /// reveal/dismiss fade for a normal successful dismiss — the window must NOT also
    /// re-animate its scale/opacity/offset on top of that: if the effect's timing is
    /// even slightly off, the window's own fade would visibly stack on top of it,
    /// which is exactly the live-vs-preview mismatch this exists to close. The one
    /// exception is `.textScatterOnly` (V6), which deliberately never touches the
    /// shell — see `DismissEffectStyle.skipsWindowFadeOnCancel` — so it needs the
    /// window's own fade left on to make the shell disappear at all.
    private func cancelRecordingAfterEffect() async {
        guard let engine = engine else { return }
        await engine.cancelRecording()

        clearPasteHint()
        cancelCoachSuggestionDisplay()

        miniWindowManager?.hide(skipAnimation: false)
        isRecorderPanelVisible = false
        engine.assistantSession.reset()
    }

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "RecorderUIManager")

    init() {}

    /// Call after SpeekEngine is created to break the circular init dependency.
    func configure(engine: SpeekEngine, recorder: Recorder) {
        self.engine = engine
        self.recorder = recorder
        setupNotifications()
    }

    // MARK: - Recorder Panel Management

    private func showRecorderPanel() {
        guard let engine = engine, let recorder = recorder else { return }
        guard SpeekSettings.shared.recordingWindowStyle != .none else { return }
        // The agent reply panel shows recording state itself; keep the pill out of the way.
        guard !AgentUpdateCenter.shared.isShowingPanel else { return }

        if miniWindowManager == nil {
            miniWindowManager = MiniWindowManager(
                engine: engine,
                recorder: recorder,
                assistantSession: engine.assistantSession,
                onRecordButtonTapped: { [weak self] in
                    Task { @MainActor in
                        await self?.toggleRecorderPanel()
                    }
                },
                onCloseTapped: { [weak self] in
                    Task { @MainActor in
                        await self?.cancelRecording()
                    }
                },
                onAssistantFollowUp: { [weak engine] text in
                    Task { @MainActor in
                        await engine?.sendAssistantFollowUp(text)
                    }
                },
                onCoachDismiss: {},
                onCoachHover: { _ in }
            )
        }
        miniWindowManager?.show()
    }

    private func hideRecorderPanel() {
        miniWindowManager?.hide()
    }

    private func rebuildVisiblePanel(previousStyle: RecorderPanelStyle) {
        guard isRecorderPanelVisible else { return }
        miniWindowManager?.destroyWindow()
        miniWindowManager = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            showRecorderPanel()
        }
    }

    /// Called when the user switches Classic / Mini / None in Configuration.
    @objc private func handleRecordingWindowStyleChange() {
        if SpeekSettings.shared.keepsRecorderVisibleWhenIdle {
            showIdlePillIfNeeded()
            return
        }
        guard isRecorderPanelVisible else { return }
        if SpeekSettings.shared.recordingWindowStyle == .none {
            hideRecorderPanel()
        } else if engine?.recordingState == .idle {
            hideRecorderPanel()
            isRecorderPanelVisible = false
        } else {
            showRecorderPanel()
        }
    }

    // MARK: - Recorder Panel Management

    func toggleRecorderPanel(modeId: UUID? = nil) async {
        guard let engine = engine else { return }
        cancelCoachSuggestionDisplay()

        if isRecorderPanelVisible {
            switch engine.recordingState {
            case .recording:
                await engine.toggleRecord(modeId: modeId)
            case .starting, .transcribing, .enhancing:
                await cancelRecording()
            case .idle:
                if engine.assistantSession.canSendFollowUp {
                    SoundManager.shared.playStartSound()
                    await engine.toggleRecord(
                        modeId: modeId,
                        isAssistantFollowUp: true
                    )
                } else if SpeekSettings.shared.keepsRecorderVisibleWhenIdle {
                    // The idle pill is on screen: a toggle starts a new recording.
                    SoundManager.shared.playStartSound()
                    await engine.toggleRecord(modeId: modeId)
                } else {
                    await dismissRecorderPanel()
                }
            case .busy:
                await dismissRecorderPanel()
            }
        } else {
            SoundManager.shared.playStartSound()
            isRecorderPanelVisible = true
            await engine.toggleRecord(modeId: modeId)
        }
    }

    func dismissRecorderPanel() async {
        guard let engine = engine else { return }

        clearPasteHint()

        cancelCoachSuggestionDisplay()
        engine.assistantSession.reset()
        if SpeekSettings.shared.keepsRecorderVisibleWhenIdle {
            // Always-show mini window: stay on screen as the idle pill.
            if !isRecorderPanelVisible { isRecorderPanelVisible = true }
            return
        }
        hideRecorderPanel()
        isRecorderPanelVisible = false
    }

    /// Shows the idle pill when "Always show" is on (called at launch and when the
    /// setting changes).
    func showIdlePillIfNeeded() {
        guard SpeekSettings.shared.keepsRecorderVisibleWhenIdle else { return }
        if isRecorderPanelVisible {
            showRecorderPanel()   // re-place on the (possibly new) edge
        } else {
            isRecorderPanelVisible = true
        }
    }

    /// Called instead of `dismissRecorderPanel()` when the transcript couldn't be
    /// auto-pasted (no editable field focused). Shows a brief "⌘V to paste" hint
    /// in the panel instead of a toast that would overlap it, then dismisses as
    /// normal. Falls back to the toast if the panel isn't on screen at all.
    func dismissRecorderPanelWithPasteHint(text: String) async {
        guard isRecorderPanelVisible, let engine = engine else {
            NotificationManager.shared.showNotification(
                title: String(localized: "Copied to clipboard — paste anywhere with ⌘V"),
                type: .success
            )
            return
        }

        cancelCoachSuggestionDisplay()
        engine.resultPreview = text
        engine.pasteHintText = String(localized: "Copied. Click a text field and press ⌘V to paste.")

        pasteHintDismissTask?.cancel()
        pasteHintDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pasteHintDismissTask = nil
            await self.dismissRecorderPanel()
        }
    }

    func resetOnLaunch() async {
        guard let engine = engine else { return }
        logger.notice("Resetting recording state on launch")
        clearPasteHint()
        cancelCoachSuggestionDisplay()
        await engine.resetRecordingSession()
        hideRecorderPanel()
        isRecorderPanelVisible = false
        engine.assistantSession.reset()
        showIdlePillIfNeeded()
    }

    func cancelRecording() async {
        guard let engine = engine else { return }
        await engine.cancelRecording()
        await dismissRecorderPanel()
    }

    // MARK: - Notification Handling

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleRecorderPanelNotification),
            name: .toggleRecorderPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissRecorderPanelNotification),
            name: .dismissRecorderPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingWindowStyleChange),
            name: .speekRecordingWindowStyleDidChange,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showIdlePillIfNeeded() }
    }

    @objc public func handleToggleRecorderPanelNotification() {
        Task {
            await toggleRecorderPanel()
        }
    }

    @objc public func handleDismissRecorderPanelNotification() {
        Task {
            switch engine?.recordingState {
            case .starting, .recording, .transcribing, .enhancing:
                await cancelRecording()
            case .idle, .busy, nil:
                await dismissRecorderPanel()
            }
        }
    }

    private func cancelCoachSuggestionDisplay() {
        coachDismissTask?.cancel()
        coachDismissTask = nil
    }

    private func clearPasteHint() {
        pasteHintDismissTask?.cancel()
        pasteHintDismissTask = nil
        engine?.pasteHintText = nil
        engine?.resultPreview = nil
    }
}
