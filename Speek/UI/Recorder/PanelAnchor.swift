import AppKit

/// Positions floating panels and keeps them locked to their anchor while they resize.
/// Bottom placement grows upward from a fixed bottom edge, top placement grows downward
/// from just under the menu bar, centre placement stays centred both ways, left/right
/// placements stay vertically centred with their edge pinned. Horizontal centring uses
/// the full screen width, not the Dock-reduced visible area, so a Dock on the side
/// never pushes a panel off centre.
enum PanelAnchor {
    enum Edge {
        case bottom, top, left, right, center
    }

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
    static func frame(for size: NSSize, edge: Edge, on screen: NSScreen, contentInset: CGFloat = 0) -> NSRect {
        let full = screen.frame
        let visible = screen.visibleFrame
        switch edge {
        case .bottom:
            return NSRect(x: full.midX - size.width / 2, y: visible.minY + bottomInset - contentInset, width: size.width, height: size.height)
        case .top:
            return NSRect(x: full.midX - size.width / 2, y: visible.maxY - topInset + contentInset - size.height, width: size.width, height: size.height)
        case .center:
            return NSRect(x: full.midX - size.width / 2, y: full.midY - size.height / 2, width: size.width, height: size.height)
        case .left:
            return NSRect(x: visible.minX + sideInset - contentInset, y: full.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: visible.maxX - sideInset + contentInset - size.width, y: full.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// Frame for a window that changed size: the anchored edge of `current` stays put and
    /// the window is re-centred on `screen` (horizontally for bottom/top, both ways for
    /// centre, vertically for the sides).
    static func resized(_ current: NSRect, to size: NSSize, edge: Edge, on screen: NSScreen?) -> NSRect {
        let full = screen?.frame
        let midX = full?.midX ?? current.midX
        let midY = full?.midY ?? current.midY
        switch edge {
        case .bottom:
            return NSRect(x: midX - size.width / 2, y: current.minY, width: size.width, height: size.height)
        case .top:
            return NSRect(x: midX - size.width / 2, y: current.maxY - size.height, width: size.width, height: size.height)
        case .center:
            return NSRect(x: midX - size.width / 2, y: midY - size.height / 2, width: size.width, height: size.height)
        case .left:
            return NSRect(x: current.minX, y: midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: current.maxX - size.width, y: midY - size.height / 2, width: size.width, height: size.height)
        }
    }
}

extension PanelPosition {
    var anchorEdge: PanelAnchor.Edge {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .left
        case .right: return .right
        }
    }
}

extension AgentPanelPosition {
    var anchorEdge: PanelAnchor.Edge {
        switch self {
        case .bottom: return .bottom
        case .center: return .center
        case .top: return .top
        }
    }
}
