import SwiftUI
import AppKit

/// Drives the panel's SwiftUI-side reveal/dismiss transition. The NSPanel itself is
/// ordered front/out instantly (see MiniRecorderPanel) — this flag lets the content
/// fade + scale in and out around that so the panel doesn't just pop on/off screen.
@MainActor
private final class PanelAppearance: ObservableObject {
    @Published var isVisible = false
}

/// Wraps the panel's SwiftUI content with the show/hide animation: a spring scale-up
/// + fade + slight upward drift on appear, mirrored (scale-down + fade) on dismiss.
private struct AnimatedPanelHost<Content: View>: View {
    @ObservedObject var appearance: PanelAppearance
    let content: Content

    var body: some View {
        content
            .scaleEffect(appearance.isVisible ? 1 : 0.85, anchor: .bottom)
            .opacity(appearance.isVisible ? 1 : 0)
            .offset(y: appearance.isVisible ? 0 : 10)
            // Blur alongside the fade so the panel melts away on dismiss instead of
            // just fading flat — shared by both widget looks since this host wraps
            // whichever WidgetVariant is currently rendered.
            .blur(radius: appearance.isVisible ? 0 : 12)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: appearance.isVisible)
    }
}

@MainActor
class MiniWindowManager {
    private var windowController: NSWindowController?
    private var panel: MiniRecorderPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var contentAttached = false
    private let appearance = PanelAppearance()
    /// Delays orderOut until the SwiftUI dismiss animation below has actually played.
    private var hideTask: Task<Void, Never>?

    private let makeView: () -> AnyView

    init(
        engine: SpeekEngine,
        recorder: Recorder,
        assistantSession: AssistantSession,
        onRecordButtonTapped: @escaping () -> Void,
        onCloseTapped: @escaping () -> Void,
        onAssistantFollowUp: @escaping (String) -> Void,
        onCoachDismiss: @escaping () -> Void,
        onCoachHover: @escaping (Bool) -> Void
    ) {
        self.makeView = {
            AnyView(
                SpeekRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    onStopTapped: onRecordButtonTapped,
                    onCancelTapped: onCloseTapped
                )
            )
        }
        _ = assistantSession
        _ = onAssistantFollowUp
        _ = onCoachDismiss
        _ = onCoachHover
    }

    func show() {
        hideTask?.cancel()
        hideTask = nil
        if panel == nil { initializeWindow() }
        attachContent()
        panel?.show()
        // Start from the hidden state and animate in on the next runloop tick, so the
        // window is already on screen (per MiniRecorderPanel.show()) before SwiftUI
        // picks up the false → true change and plays the reveal spring.
        appearance.isVisible = false
        DispatchQueue.main.async { [weak self] in
            self?.appearance.isVisible = true
        }
    }

    /// - Parameter skipAnimation: True right after the panel content already played its
    ///   own full dismiss effect (see DismissEffectStyle / RecorderUIManager.
    ///   cancelRecordingAfterEffect) — the content is already invisible by then, so
    ///   layering this window's own scale/opacity/offset spring on top would be
    ///   redundant at best and, if the effect's timing is even slightly off, would
    ///   visibly double up with it. Every other caller keeps the normal animated fade.
    func hide(skipAnimation: Bool = false) {
        guard panel != nil else { return }
        hideTask?.cancel()
        appearance.isVisible = false
        guard !skipAnimation else {
            hideTask = nil
            panel?.orderOut(nil)
            detachContent()
            return
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.detachContent()
        }
    }

    func destroyWindow() {
        hideTask?.cancel()
        hideTask = nil
        deinitializeWindow()
    }

    private func initializeWindow() {
        deinitializeWindow()
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        let newPanel = MiniRecorderPanel(contentRect: metrics)
        let hostingController = NSHostingController<AnyView>(rootView: AnyView(EmptyView()))
        newPanel.contentView = hostingController.view
        self.hostingController = hostingController
        panel = newPanel
        windowController = NSWindowController(window: newPanel)
    }

    /// Mount the live SwiftUI tree only while the panel is on screen. Once hidden the
    /// tree is swapped for EmptyView (see detachContent) so no TimelineView/animation
    /// keeps the run loop busy behind an ordered-out window.
    private func attachContent() {
        guard !contentAttached else { return }
        hostingController?.rootView = AnyView(
            AnimatedPanelHost(appearance: appearance, content: makeView())
        )
        contentAttached = true
    }

    private func detachContent() {
        hostingController?.rootView = AnyView(EmptyView())
        contentAttached = false
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        hostingController = nil
        contentAttached = false
        panel = nil
    }
}
