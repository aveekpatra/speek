import AppKit

/// Where the floating panels (recorder pill and agent reply) sit on screen.
enum PanelPlacement {
    case bottom, top, left, right

    /// Placement the current settings ask for: the always-show edge, else bottom centre.
    @MainActor static var current: PanelPlacement {
        let settings = SpeekSettings.shared
        guard settings.keepsRecorderVisibleWhenIdle else { return .bottom }
        switch settings.alwaysShowEdge {
        case .top: return .top
        case .left: return .left
        case .right: return .right
        }
    }
}

/// Positions floating panels and keeps them locked to their anchor while they resize.
/// Bottom placement grows upward from a fixed bottom edge, top placement grows downward
/// from just under the menu bar, left/right placements stay vertically centred. The
/// horizontal centre (or the pinned side edge) never moves either.
enum PanelAnchor {
    static let topInset: CGFloat = 3
    static let bottomInset: CGFloat = 26
    static let sideInset: CGFloat = 3

    /// The screen the user is working on: the one under the pointer, else the main one.
    static var screen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Frame for a freshly shown panel of `size`.
    static func frame(for size: NSSize, placement: PanelPlacement, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        switch placement {
        case .bottom:
            return NSRect(x: visible.midX - size.width / 2, y: visible.minY + bottomInset, width: size.width, height: size.height)
        case .top:
            return NSRect(x: visible.midX - size.width / 2, y: visible.maxY - topInset - size.height, width: size.width, height: size.height)
        case .left:
            return NSRect(x: visible.minX + sideInset, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: visible.maxX - sideInset - size.width, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// Frame for a panel that changed size: the anchored edge of `current` stays put.
    static func resized(_ current: NSRect, to size: NSSize, placement: PanelPlacement) -> NSRect {
        switch placement {
        case .bottom:
            return NSRect(x: current.midX - size.width / 2, y: current.minY, width: size.width, height: size.height)
        case .top:
            return NSRect(x: current.midX - size.width / 2, y: current.maxY - size.height, width: size.width, height: size.height)
        case .left:
            return NSRect(x: current.minX, y: current.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: current.maxX - size.width, y: current.midY - size.height / 2, width: size.width, height: size.height)
        }
    }
}
