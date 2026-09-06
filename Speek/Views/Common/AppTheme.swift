import SwiftUI

enum AppTheme {
    enum Accent {
        static let primary = Color.accentColor
        static let fillSubtle = primary.opacity(0.10)
        static let fill = primary.opacity(0.14)
        static let fillStrong = primary.opacity(0.28)
        static let border = primary.opacity(0.40)
        static let disabled = primary.opacity(0.50)
        static let foreground = primary.opacity(0.65)
        static let strong = primary.opacity(0.80)
        static let shadow = primary.opacity(0.20)
    }

    enum Surface {
        static let card = Color.primary.opacity(0.055)
        static let materialCard = Color.primary.opacity(0.045)
        static let subtle = Color.primary.opacity(0.045)
        static let controlActive = Color.primary.opacity(0.075)
        static let control = Color(nsColor: .controlBackgroundColor)
        /// Quiet neutral fill for small native-style tags/chips (e.g. Finder/Reminders tags).
        static let quaternaryFill = Color(nsColor: .quaternarySystemFill)
        static let window = Color(nsColor: .windowBackgroundColor)
        static let sidePanelOverlay = Color(nsColor: .windowBackgroundColor).opacity(0.50)
        static let clear = Color.clear

        /// Codex-inspired app background. Light: warm paper, Dark: neutral charcoal.
        static let canvas = Color("AppCanvas")
        /// Floating content canvas. Light: soft white, Dark: raised charcoal.
        static let cardSolid = Color("AppCardSurface")
    }

    enum Border {
        static let subtle = Color(nsColor: .separatorColor).opacity(0.28)
        static let card = Color(nsColor: .separatorColor).opacity(0.35)
        static let control = Color(nsColor: .separatorColor)
        static let tint = Color.primary.opacity(0.12)
        static let sidePanelOuter = Color.white.opacity(0.12)
        /// Hairline border around the floating white card canvas.
        static let canvasCard = Color("AppCardStroke")
    }

    enum Selection {
        static let fill = Color.primary.opacity(0.10)
        static let border = Color.primary.opacity(0.14)
        static let foreground = Color.primary.opacity(0.78)
    }

    enum Status {
        static let success = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let positive = Color(nsColor: .systemGreen)
        static let info = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.75)
        static let infoStrong = Color(nsColor: .systemBlue)
        static let warning = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let warningStrong = Color(nsColor: .systemOrange)
        static let error = Color(nsColor: .systemRed)
    }

    enum Data {
        static let transcript = Color.indigo
        static let audio = Color.teal
        static let enhancement = Color.mint
        static let purple = Color(nsColor: .systemPurple)
        static let yellow = Color(nsColor: .systemYellow)
        static let orange = Color(nsColor: .systemOrange)
    }

    enum Sidebar {
        static let dashboard = Color(hex: "#D1783F")
        static let modes = Color(hex: "#6E75E8")
        static let models = Color(hex: "#A87954")
        static let audio = Color(hex: "#8B8B91")
        static let dictionary = Color(hex: "#4B8AF0")
        static let fallback = Color(hex: "#8B8B91")
        static let license = Color(hex: "#54B56A")
    }

    enum Waveform {
        static let hoverBubble = Color.primary.opacity(0.74)
        static let hoverMarker = Color.primary.opacity(0.68)
        static let playedLower = Color.primary
        static let playedUpper = Color.primary.opacity(0.80)
        static let unplayedLower = Color.primary.opacity(0.30)
        static let unplayedUpper = Color.primary.opacity(0.20)
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let muted = secondary.opacity(0.70)
        static let disabled = Color(nsColor: .disabledControlTextColor)
        static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)
    }

    enum NativeText {
        static let primary = NSColor.labelColor
    }

    enum Action {
        static let primaryFill = Accent.primary
        static let primaryForeground = Text.onAccent
        static let secondaryForeground = Text.primary
        static let disabledFill = Surface.controlActive
        static let disabledForeground = Text.disabled
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
    }
}
