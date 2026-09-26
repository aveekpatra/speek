import SwiftUI
import AppKit
import Sparkle

@main
struct SpeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra("Speek", systemImage: "waveform") {
            Button("Open Speek") { SpeekMainWindow.shared.show() }
            Button("Speak") { AssistantController.shared.toggleVoice() }
            Button("Type a request") { AssistantController.shared.show(typing: true) }
            Button("Circle screen context") { AssistantController.shared.circleContext() }
            Divider()
            Button("Settings...") { AssistantSettingsWindow.shared.show() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit Speek") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") { SpeekMainWindow.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = value
    }

    func checkForUpdates() {
        // This is for manual checks - will show UI
        updaterController.checkForUpdates(nil)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

/// Menu bar entry that opens the guided permissions window.
struct PermissionsMenuItem: View {
    @ObservedObject private var permissions = PermissionsCenter.shared

    var body: some View {
        Button(permissions.allGranted ? "Permissions..." : "Permissions (action needed)...") {
            PermissionsCenter.shared.showGuide()
        }
    }
}

/// Observes ThemeManager and applies skin + font live to the main window content.
/// Light/Dark keep the current look (nil overrides); Warm/Midnight paint a background and tint.
struct ThemedRootView<Content: View>: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(theme.resolvedBackground.map { AnyView($0.ignoresSafeArea()) } ?? AnyView(Color.clear))
            .preferredColorScheme(theme.skin.colorScheme)
            .tint(theme.resolvedAccent)
            .fontDesign(theme.fontDesign)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
