import SwiftUI

/// The main window: Liquid Glass sidebar + detail column, mirroring Superwhisper.
struct MainWindowView: View {
    @ObservedObject private var navigation = SpeekNavigation.shared
    @ObservedObject private var settings = SpeekSettings.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SpeekSidebar(navigation: navigation)
                .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        } detail: {
            NavigationStack(path: $navigation.path) {
                detail
                    .navigationDestination(for: SpeekRoute.self) { route in
                        switch route {
                        case .modeDetail(let id): ModeDetailPage(modeID: id)
                        case .advancedConfiguration: AdvancedConfigurationPage()
                        }
                    }
            }
            .frame(minWidth: 560, minHeight: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .speekNavigate)) { notification in
            if let route = notification.userInfo?["page"] as? String, let page = SpeekPage(route: route) {
                navigation.open(page)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            // Legacy routes from the inherited engine ("AI Models", "History", ...)
            guard let destination = notification.userInfo?["destination"] as? String else { return }
            switch destination {
            case "AI Models": navigation.open(.modelsLibrary)
            case "History": navigation.open(.history)
            case "Dictionary": navigation.open(.vocabulary)
            case "Settings": navigation.open(.configuration)
            default: break
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.page {
        case .home: HomePage()
        case .modes: ModesPage()
        case .vocabulary: VocabularyPage()
        case .agents: AgentsPage()
        case .configuration: ConfigurationPage()
        case .sound: SoundPage()
        case .modelsLibrary: ModelsLibraryPage()
        case .history: HistoryPage()
        case .about: AboutPage()
        }
    }
}

/// Toolbar shared by most pages: microphone picker on the trailing edge.
struct SpeekStandardToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            MicrophoneToolbarMenu()
        }
    }
}

/// Right-aligned search field (plus optional extra controls) for list pages.
struct SpeekSearchToolbar<Extra: View>: ToolbarContent {
    @Binding var text: String
    let prompt: String
    @ViewBuilder var extra: () -> Extra

    init(text: Binding<String>, prompt: String, @ViewBuilder extra: @escaping () -> Extra) {
        _text = text
        self.prompt = prompt
        self.extra = extra
    }

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(width: 200)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        // Fixed spacer: keeps the extra control in its own glass group instead of
        // merging into the search field's capsule.
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            extra()
        }
    }
}

extension SpeekSearchToolbar where Extra == EmptyView {
    init(text: Binding<String>, prompt: String) {
        self.init(text: text, prompt: prompt, extra: { EmptyView() })
    }
}
