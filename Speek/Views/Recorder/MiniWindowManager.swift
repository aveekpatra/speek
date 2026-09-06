import SwiftUI
import AppKit

/// Drives the panel's SwiftUI-side reveal/dismiss transition. The NSPanel itself is
/// ordered front/out instantly (see MiniRecorderPanel) — this flag lets the content
/// fade + scale in and out around that so the panel doesn't just pop on/off screen.
@MainActor
private final class PanelAppearance: ObservableObject {
    @Published var isVisible = false
}

/// Wraps the panel's SwiftUI content with the show/hide animation. Appearing is a
/// bubbly inflate, like Spotlight on macOS 26: the glass starts as a squashed drop,
/// springs past full size and settles with a visible bounce. Dismissing is a quick,
/// soft deflate so the pill gets out of the way without theatrics.
private struct AnimatedPanelHost<Content: View>: View {
    @ObservedObject var appearance: PanelAppearance
    let content: Content

    private var showAnimation: Animation { .spring(response: 0.55, dampingFraction: 0.52, blendDuration: 0.1) }
    private var hideAnimation: Animation { .easeIn(duration: 0.16) }

    var body: some View {
        let visible = appearance.isVisible
        content
            // Wider than tall while hidden: a drop that inflates rather than a card
            // that zooms.
            .scaleEffect(x: visible ? 1 : 0.55, y: visible ? 1 : 0.35, anchor: .bottom)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .blur(radius: visible ? 0 : 6)
            .animation(visible ? showAnimation : hideAnimation, value: visible)
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
