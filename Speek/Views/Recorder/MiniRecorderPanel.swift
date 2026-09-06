import SwiftUI
import AppKit

class MiniRecorderPanel: NSPanel {
    // Never become the key/main window: the recorder pops up over whatever the user
    // was typing in (a chat box, etc.). Stealing key status drops their text field's
    // focus, so Enter after dictation wouldn't land there. Buttons inside a
    // nonactivating panel still receive clicks, and the global CGEvent tap
    // (ShortcutMonitor) catches Escape / mode digits without needing key status.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }
    
    private func configurePanel() {
        isFloatingPanel = true
        level = .floating
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        // Window is dragged manually (mouseDown/mouseDragged below) instead of the
        // system background drag — a system drag session triggers macOS edge
        // tiling/snapping, which blocks free placement near screen edges.
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }
    
    static func calculateWindowMetrics() -> NSRect {
        // Host stays large enough for assistant output; SwiftUI controls the visible
        // pill size and aligns it to the anchored edge (see SpeekRecorderView.contentInsets).
        let size = NSSize(width: 540, height: 430)
        guard let screen = PanelAnchor.screen else {
            return NSRect(origin: .zero, size: size)
        }
        let placement = MainActor.assumeIsolated { PanelPlacement.current }
        var frame = PanelAnchor.frame(for: size, placement: placement, on: screen)
        // The content already keeps its own gap from the anchored edge; pull the host
        // back by that much so the visible pill lands exactly on the anchor.
        let insets = SpeekRecorderView<SpeekEngine>.contentInsets(for: placement)
        switch placement {
        case .bottom: frame.origin.y -= insets.bottom
        case .top: frame.origin.y += insets.top
        case .left: frame.origin.x -= insets.leading
        case .right: frame.origin.x += insets.trailing
        }
        return frame
    }

    func show() {
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        applyFrame { setFrame(metrics, display: true) }
        // orderFrontRegardless (not makeKeyAndOrderFront) so the panel shows without
        // taking focus away from the user's current text field.
        orderFrontRegardless()
    }

    // MARK: - Frame lock (Magnet & friends)
    // Window managers like Magnet reposition windows via the Accessibility API
    // when a drag ends near a screen edge. While the panel is on screen, only
    // moves we initiate ourselves (show() and the manual drag below) may change
    // the frame; anything else is ignored so the widget stays where the user
    // dropped it.

    private var allowsFrameChange = false

    private func applyFrame(_ move: () -> Void) {
        allowsFrameChange = true
        move()
        allowsFrameChange = false
    }

    private func frameChangeAllowed() -> Bool {
        if allowsFrameChange || !isVisible { return true }
        NSLog("Speek MiniRecorderPanel: blocked external frame change")
        return false
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard frameChangeAllowed() else { return }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        guard frameChangeAllowed() else { return }
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        guard frameChangeAllowed() else { return }
        super.setFrameOrigin(point)
    }

    // MARK: - Manual drag (no macOS tiling/snapping)
    // Clicks that no SwiftUI control consumes fall through to the panel; we move
    // the window ourselves so the system tiling engine never kicks in.

    private var dragAnchorInWindow: NSPoint?

    override func mouseDown(with event: NSEvent) {
        NSLog("Speek MiniRecorderPanel: manual drag started")
        dragAnchorInWindow = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchorInWindow else { return }
        let mouseOnScreen = NSEvent.mouseLocation
        applyFrame {
            setFrameOrigin(NSPoint(x: mouseOnScreen.x - anchor.x,
                                   y: mouseOnScreen.y - anchor.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchorInWindow = nil
    }

    // Don't let AppKit nudge the frame back on screen — the user can park the
    // widget anywhere, including flush against screen edges.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
