import SwiftUI
import LaunchAtLogin

struct ConfigurationPage: View {
    var body: some View {
        ConfigurationRootPage()
    }
}

// MARK: - Root

private struct ConfigurationRootPage: View {
    @ObservedObject private var settings = SpeekSettings.shared
    @ObservedObject private var navigation = SpeekNavigation.shared
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var shortcutResetID = 0

    var body: some View {
        SpeekPageScroll {
            appearance
            keyboardShortcuts
            application
            SpeekGroup {
                SpeekNavigationRow(title: "Advanced settings") {
                    navigation.push(.advancedConfiguration)
                }
            }
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
    }

    // MARK: Appearance

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Appearance")
            SpeekGroup {
                SpeekRow("Theme") {
                    HStack(spacing: 18) {
                        ForEach(AppearanceTheme.allCases) { theme in
                            SpeekChoiceCard(title: theme.displayName, isSelected: settings.theme == theme) {
                                settings.theme = theme
                            } preview: {
                                ThemePreview(theme: theme)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                SpeekRow("Recording window") {
                    HStack(spacing: 18) {
                        ForEach(RecordingWindowStyle.allCases) { style in
                            SpeekChoiceCard(title: style.displayName, isSelected: settings.recordingWindowStyle == style, previewSize: CGSize(width: 96, height: 46), cornerRadius: 10, tintsWhenSelected: true) {
                                settings.recordingWindowStyle = style
                            } preview: {
                                RecordingWindowPreview(style: style)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                if settings.recordingWindowStyle == .mini {
                    SpeekRow("Always show", help: "If enabled, the mini window will always be visible. Useful if you want to activate with your mouse.") {
                        Toggle("", isOn: $settings.alwaysShowMiniWindow).labelsHidden().toggleStyle(.switch)
                    }
                    if settings.alwaysShowMiniWindow {
                        SpeekRow("Position", help: "Which screen edge the mini window sits on.") {
                            SpeekSegmentedPicker(selection: $settings.alwaysShowEdge, options: RecorderEdge.allCases) { $0.displayName }
                        }
                    }
                }
            }
        }
    }

    // MARK: Shortcuts

    private var keyboardShortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Keyboard Shortcuts")
            SpeekGroup {
                SpeekRow("Toggle Recording", subtitle: "Starts and stops recordings") {
                    HStack(spacing: 10) {
                        ResetShortcutButton {
                            ShortcutStore.setShortcut(.command, for: .primaryRecording)
                            recordingShortcutManager.primaryRecordingShortcut = .custom
                            recordingShortcutManager.primaryRecordingShortcutMode = .toggle
                            recordingShortcutManager.updateShortcutStatus()
                            shortcutResetID += 1
                        }
                        ShortcutRecorder(action: .primaryRecording) {
                            recordingShortcutManager.primaryRecordingShortcut = .custom
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .id("primary-\(shortcutResetID)")
                    }
                }
                SpeekRow("Cancel Recording", subtitle: "Discards the active recording") {
                    HStack(spacing: 10) {
                        ResetShortcutButton {
                            ShortcutStore.setShortcut(Self.defaultCancelShortcut, for: .cancelRecorder)
                            shortcutResetID += 1
                        }
                        ShortcutRecorder(action: .cancelRecorder, defaultShortcut: Self.defaultCancelShortcut)
                            .id("cancel-\(shortcutResetID)")
                    }
                }
                SpeekRow("Change mode", subtitle: "Activates the mode switcher") {
                    HStack(spacing: 10) {
                        ResetShortcutButton {
                            ShortcutStore.setShortcut(Self.defaultChangeModeShortcut, for: .changeMode)
                            shortcutResetID += 1
                        }
                        ShortcutRecorder(action: .changeMode, defaultShortcut: Self.defaultChangeModeShortcut)
                            .id("mode-\(shortcutResetID)")
                    }
                }
                SpeekRow("Push to Talk", subtitle: "Hold to record, release when done") {
                    HStack(spacing: 10) {
                        if recordingShortcutManager.secondaryRecordingShortcut == .custom {
                            Button {
                                ShortcutStore.setShortcut(nil, for: .secondaryRecording)
                                recordingShortcutManager.secondaryRecordingShortcut = .none
                                recordingShortcutManager.updateShortcutStatus()
                                shortcutResetID += 1
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove push to talk shortcut")
                        }
                        ShortcutRecorder(action: .secondaryRecording) {
                            recordingShortcutManager.secondaryRecordingShortcut = .custom
                            recordingShortcutManager.secondaryRecordingShortcutMode = .pushToTalk
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .id("ptt-\(shortcutResetID)")
                    }
                }
                SpeekRow("Mouse shortcut", subtitle: "Tap to toggle, or hold and release when done") {
                    Picker("", selection: $recordingShortcutManager.isMiddleClickToggleEnabled) {
                        Text("Off").tag(false)
                        Text("Middle click").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Application

    private var application: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeekSectionHeader("Application")
            SpeekGroup {
                SpeekRow("Update application") {
                    SpeekPillButton(title: "Check for Updates...") {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)
                }
                SpeekRow("Keep running in the menu bar", help: "Closing the main window keeps Speek running in the menu bar so shortcuts, dictation and agent replies keep working. Turn off to quit Speek when the window closes.") {
                    Toggle("", isOn: $settings.keepRunningInMenuBar).labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Automatically check for updates", help: "Speek checks GitHub releases for new versions in the background.") {
                    Toggle("", isOn: Binding(
                        get: { updaterViewModel.automaticallyChecksForUpdates },
                        set: { updaterViewModel.setAutomaticallyChecksForUpdates($0); settings.automaticallyCheckForUpdates = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Launch on login", help: "Start Speek automatically when you log in to your Mac.") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = $0; LaunchAtLogin.isEnabled = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Error logging", help: "Writes detailed diagnostics to the app folder. Useful when reporting a bug.") {
                    Toggle("", isOn: $settings.errorLogging).labelsHidden().toggleStyle(.switch)
                }
                SpeekRow("Keep recordings for", help: "Audio files older than this are deleted. Transcripts are always kept.") {
                    Picker("", selection: $settings.recordingRetention) {
                        ForEach(RecordingRetention.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    static let defaultCancelShortcut = Shortcut.key(keyCode: 53, modifierFlags: []) // esc
    static let defaultChangeModeShortcut = Shortcut.key(keyCode: 40, modifierFlags: [.option, .shift]) // ⌥⇧K
}

private struct ResetShortcutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Reset to default")
    }
}

// MARK: - Previews used by the choice cards

/// Uses macOS's own Appearance thumbnails (the ones System Settings shows) so the
/// picker matches the system, with a drawn fallback if the asset is unavailable.
private struct ThemePreview: View {
    let theme: AppearanceTheme

    private static let systemBundle = Bundle(url: URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/Appearance.appex"))

    private var assetName: String {
        switch theme {
        case .auto: return "AppearanceAuto"
        case .light: return "AppearanceLight"
        case .dark: return "AppearanceDark"
        }
    }

    var body: some View {
        if let image = Self.systemBundle?.image(forResource: assetName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            switch theme {
            case .auto:
                HStack(spacing: 0) {
                    miniWindow(dark: false)
                    miniWindow(dark: true)
                }
            case .light:
                miniWindow(dark: false)
            case .dark:
                miniWindow(dark: true)
            }
        }
    }

    private func miniWindow(dark: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.18, green: 0.15, blue: 0.40), Color(red: 0.06, green: 0.05, blue: 0.18)]
                    : [Color(red: 0.65, green: 0.80, blue: 0.98), Color(red: 0.95, green: 0.90, blue: 0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(dark ? Color(white: 0.16) : Color.white.opacity(0.92))
                .frame(width: 40, height: 24)
                .padding(5)
                .offset(x: 4, y: 4)
        }
    }
}

private struct RecordingWindowPreview: View {
    let style: RecordingWindowStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
            switch style {
            case .classic:
                // Classic panel: waveform area over a lighter bottom bar.
                VStack(spacing: 0) {
                    waveform(bars: 24, height: 12, weight: 1.6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .frame(height: 5)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)
                }
                .frame(width: 42, height: 27)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black))
            case .mini:
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: 36, height: 13)
                    .overlay(waveform(bars: 7, height: 7, weight: 1.6))
            case .none:
                Image(systemName: "eye.slash")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func waveform(bars: Int, height: CGFloat, weight: CGFloat) -> some View {
        HStack(spacing: weight * 0.7) {
            ForEach(0..<bars, id: \.self) { index in
                let phase = Double(index) / Double(bars) * .pi * 2
                Capsule()
                    .fill(Color.white)
                    .frame(width: weight, height: max(weight, height * (0.3 + 0.7 * abs(sin(phase * 2.7 + 0.6)))))
            }
        }
    }
}
