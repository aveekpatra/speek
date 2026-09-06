import SwiftUI

// MARK: - Color(hex:)

extension Color {
    /// Creates a Color from a hex string like "#F4F3EE" or "F4F3EE".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        switch cleaned.count {
        case 8: // RRGGBBAA
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default: // RRGGBB (and fallback)
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - AppSkin

enum AppSkin: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    var sfSymbol: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// Forced color scheme for the skin. nil means follow the OS.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    // Light/Dark use Codex-inspired asset colors and semantic app tokens.
    var background: Color? { nil }
    var surface: Color? { nil }
    var primaryText: Color? { nil }
    var secondaryText: Color? { nil }
    var accent: Color? { nil }
    var border: Color? { nil }
}

// MARK: - AppFontChoice

enum AppFontChoice: String, CaseIterable, Identifiable {
    case system
    case rounded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        }
    }
}

// MARK: - ThemeManager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private let skinKey = "appSkin"
    private let fontKey = "appFontChoice"

    @Published var skin: AppSkin {
        didSet { UserDefaults.standard.set(skin.rawValue, forKey: skinKey) }
    }

    @Published var fontChoice: AppFontChoice {
        didSet { UserDefaults.standard.set(fontChoice.rawValue, forKey: fontKey) }
    }

    init() {
        let savedSkin = UserDefaults.standard.string(forKey: skinKey)
        skin = savedSkin.flatMap(AppSkin.init(rawValue:)) ?? .system

        let savedFont = UserDefaults.standard.string(forKey: fontKey)
        fontChoice = savedFont.flatMap(AppFontChoice.init(rawValue:)) ?? .rounded
    }

    /// Non-persisting initializer for previews and tests. Assigning in init does not
    /// fire the @Published didSet, so this never writes to the real UserDefaults keys.
    init(skin: AppSkin, fontChoice: AppFontChoice) {
        self.skin = skin
        self.fontChoice = fontChoice
    }

    // MARK: Resolved values (fall back to native AppTheme colors when skin override is nil)

    /// Background to paint behind content. ContentView also uses AppTheme.Surface.canvas.
    var resolvedBackground: Color? { skin.background }

    /// Accent/tint follows the app AccentColor asset unless a future skin overrides it.
    var resolvedAccent: Color? { skin.accent ?? AppTheme.Accent.primary }

    var fontDesign: Font.Design { fontChoice.design }

    var resolvedSurface: Color { skin.surface ?? AppTheme.Surface.card }
    var resolvedPrimaryText: Color { skin.primaryText ?? AppTheme.Text.primary }
    var resolvedSecondaryText: Color { skin.secondaryText ?? AppTheme.Text.secondary }
    var resolvedBorder: Color { skin.border ?? AppTheme.Border.card }
}
