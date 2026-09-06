import SwiftUI

/// Top-level destinations in the main window sidebar.
enum SpeekPage: String, CaseIterable, Identifiable, Hashable {
    case home
    case modes
    case vocabulary
    case agents
    case configuration
    case sound
    case modelsLibrary
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .modes: return "Modes"
        case .vocabulary: return "Vocabulary"
        case .agents: return "Agent Panel"
        case .configuration: return "Configuration"
        case .sound: return "Sound"
        case .modelsLibrary: return "Models library"
        case .history: return "History"
        case .about: return "Speek"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .modes: return "sparkle"
        case .vocabulary: return "text.book.closed.fill"
        case .agents: return "apple.terminal.fill"
        case .configuration: return "gearshape.fill"
        case .sound: return "speaker.wave.2.fill"
        case .modelsLibrary: return "books.vertical.fill"
        case .history: return "clock.arrow.circlepath"
        case .about: return "waveform"
        }
    }

    var tileColor: Color {
        switch self {
        case .home: return Color(red: 0.98, green: 0.45, blue: 0.20)
        case .modes: return Color(red: 0.20, green: 0.50, blue: 0.98)
        case .vocabulary: return Color(red: 0.20, green: 0.55, blue: 0.98)
        case .agents: return Color(red: 0.20, green: 0.52, blue: 0.98)
        case .configuration: return Color(white: 0.45)
        case .sound: return Color(white: 0.45)
        case .modelsLibrary: return Color(white: 0.45)
        case .history: return Color(red: 0.42, green: 0.40, blue: 0.95)
        case .about: return Color.accentColor
        }
    }

    /// Sidebar sections, in display order (a gap is drawn between sections).
    static let sidebarSections: [[SpeekPage]] = [
        [.home],
        [.modes, .vocabulary, .agents],
        [.configuration, .sound, .modelsLibrary],
        [.history]
    ]

    /// Route used by menu bar / notifications to open a page.
    init?(route: String) {
        self.init(rawValue: route)
    }
}

/// Pushed screens inside the detail column.
enum SpeekRoute: Hashable {
    case modeDetail(UUID)
    case advancedConfiguration
}

/// Navigation state shared between the sidebar, the detail column and external
/// callers (menu bar, deep links).
@MainActor
final class SpeekNavigation: ObservableObject {
    static let shared = SpeekNavigation()

    @Published var page: SpeekPage = .home
    @Published var path: [SpeekRoute] = []

    func open(_ page: SpeekPage) {
        self.page = page
        path = []
    }

    func push(_ route: SpeekRoute) {
        path = [route]
    }

    func pop() {
        path = []
    }
}
