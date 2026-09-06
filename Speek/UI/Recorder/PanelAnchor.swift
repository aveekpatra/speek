import AppKit

/// Positions floating panels and keeps them locked to their anchor while they resize.
/// Bottom placement grows upward from a fixed bottom edge, top placement grows downward
/// from just under the menu bar, left/right placements stay vertically centred. Bottom
/// and top are always horizontally centred on the screen; a side placement keeps its
/// edge pinned. Nothing else ever moves.
enum PanelAnchor {
    static let topInset: CGFloat = 3
    static let bottomInset: CGFloat = 26
    static let sideInset: CGFloat = 3

    /// The screen the user is working on: the one under the pointer, else the main one.
    static var screen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Frame for a freshly shown window of `size`. `contentInset` is the gap the window
    /// keeps between its own edge and the visible content on the anchored side (room for
    /// the glass shadow); the window is pulled back by that much so the visible content,
    /// not the transparent margin, lands on the anchor.
    static func frame(for size: NSSize, position: PanelPosition, on screen: NSScreen, contentInset: CGFloat = 0) -> NSRect {
        let visible = screen.visibleFrame
        switch position {
        case .bottom:
            return NSRect(x: visible.midX - size.width / 2, y: visible.minY + bottomInset - contentInset, width: size.width, height: size.height)
        case .top:
            return NSRect(x: visible.midX - size.width / 2, y: visible.maxY - topInset + contentInset - size.height, width: size.width, height: size.height)
        case .left:
            return NSRect(x: visible.minX + sideInset - contentInset, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: visible.maxX - sideInset + contentInset - size.width, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// Frame for a window that changed size: the anchored edge of `current` stays put and
    /// the window is re-centred on `screen` (bottom/top horizontally, sides vertically).
    static func resized(_ current: NSRect, to size: NSSize, position: PanelPosition, on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame
        switch position {
        case .bottom:
            return NSRect(x: (visible?.midX ?? current.midX) - size.width / 2, y: current.minY, width: size.width, height: size.height)
        case .top:
            return NSRect(x: (visible?.midX ?? current.midX) - size.width / 2, y: current.maxY - size.height, width: size.width, height: size.height)
        case .left:
            return NSRect(x: current.minX, y: (visible?.midY ?? current.midY) - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: current.maxX - size.width, y: (visible?.midY ?? current.midY) - size.height / 2, width: size.width, height: size.height)
        }
    }
}
