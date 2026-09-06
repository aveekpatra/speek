import Foundation
import AppKit
import SwiftUI
import Combine

// MARK: - Enumerations backing Superwhisper-style settings

/// Screen edge for the always-shown mini strip. Bottom is deliberately excluded
/// (the Dock lives there).
enum RecorderEdge: String, CaseIterable, Identifiable {
    case top, left, right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

enum RecordingWindowStyle: String, CaseIterable, Identifiable {
    case classic
    case mini
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .mini: return "Mini"
        case .none: return "None"
        }
    }
}

enum AppearanceTheme: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SoundEffectsStyle: String, CaseIterable, Identifiable {
    case simple
    case classic
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .classic: return "Classic"
        case .off: return "Off"
        }
    }
}

enum PlaybackWhenRecording: String, CaseIterable, Identifiable {
    case pause
    case mute
    case nothing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pause: return "Pause"
        case .mute: return "Mute"
        case .nothing: return "Do nothing"
        }
    }
}

enum ClipboardContentPolicy: String, CaseIterable, Identifiable {
    case keep
    case replace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep: return "Keep what I have copied"
        case .replace: return "Replace with result text"
        }
    }
}

enum RecordingRetention: Int, CaseIterable, Identifiable {
    case forever = 0
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30
    case threeMonths = 90

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .forever: return "Forever"
        case .oneDay: return "1 day"
        case .oneWeek: return "1 week"
        case .oneMonth: return "1 month"
        case .threeMonths: return "3 months"
        }
    }
}

enum ModelActiveDuration: Int, CaseIterable, Identifiable {
    case never = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600
    case always = -1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .never: return "Unload immediately"
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .always: return "Always loaded"
        }
    }
}

enum StatsRange: String, CaseIterable, Identifiable {
    case allTime
    case today
    case week
    case month

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allTime: return "All time"
        case .today: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .allTime: return nil
        case .today: return calendar.startOfDay(for: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        }
    }
}

// MARK: - Settings store

/// Single observable store for the Superwhisper-style settings surface. Every property
/// is backed by UserDefaults so the rest of the engine (which reads the legacy keys
/// directly) keeps working. New keys are prefixed `speek.`; legacy keys are reused
/// where the engine already consumes them.
@MainActor
final class SpeekSettings: ObservableObject {
    static let shared = SpeekSettings()

    private let defaults = UserDefaults.standard

    // Appearance
    @Published var theme: AppearanceTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            Self.applyAppearance(theme)
        }
    }

    /// Sets the app-wide appearance. `nil` follows the system, which SwiftUI's
    /// `preferredColorScheme(nil)` does not reliably restore once an explicit
    /// scheme was applied.
    static func applyAppearance(_ theme: AppearanceTheme) {
        switch theme {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    @Published var recordingWindowStyle: RecordingWindowStyle {
        didSet {
            defaults.set(recordingWindowStyle.rawValue, forKey: Keys.recordingWindowStyle)
            NotificationCenter.default.post(name: .speekRecordingWindowStyleDidChange, object: nil)
        }
    }
    /// Mini window only: keep the pill on screen when idle so a click starts recording.
    @Published var alwaysShowMiniWindow: Bool {
        didSet {
            defaults.set(alwaysShowMiniWindow, forKey: Keys.alwaysShowMini)
            NotificationCenter.default.post(name: .speekRecordingWindowStyleDidChange, object: nil)
        }
    }

    @Published var alwaysShowEdge: RecorderEdge {
        didSet {
            defaults.set(alwaysShowEdge.rawValue, forKey: Keys.alwaysShowEdge)
            NotificationCenter.default.post(name: .speekRecordingWindowStyleDidChange, object: nil)
        }
    }

    var keepsRecorderVisibleWhenIdle: Bool {
        recordingWindowStyle == .mini && alwaysShowMiniWindow
    }

    // Application
    @Published var automaticallyCheckForUpdates: Bool { didSet { defaults.set(automaticallyCheckForUpdates, forKey: Keys.autoUpdate) } }
    @Published var errorLogging: Bool { didSet { defaults.set(errorLogging, forKey: Keys.errorLogging) } }
    @Published var recordingRetention: RecordingRetention {
        didSet {
            defaults.set(recordingRetention.rawValue, forKey: Keys.recordingRetention)
            // Legacy audio cleanup keys consumed by AudioCleanupManager.
            defaults.set(recordingRetention != .forever, forKey: "IsAudioCleanupEnabled")
            defaults.set(max(recordingRetention.rawValue, 1), forKey: "AudioRetentionPeriod")
        }
    }

    // Advanced: application
    @Published var startRecordingOnMenubarClick: Bool { didSet { defaults.set(startRecordingOnMenubarClick, forKey: Keys.menubarClickRecords) } }
    @Published var alwaysClose: Bool { didSet { defaults.set(alwaysClose, forKey: Keys.alwaysClose) } }
    @Published var modelActiveDuration: ModelActiveDuration { didSet { defaults.set(modelActiveDuration.rawValue, forKey: Keys.modelActiveDuration) } }
    @Published var appFolderPath: String { didSet { defaults.set(appFolderPath, forKey: Keys.appFolder) } }

    // Advanced: text input
    @Published var clipboardContent: ClipboardContentPolicy {
        didSet {
            defaults.set(clipboardContent.rawValue, forKey: Keys.clipboardContent)
            defaults.set(clipboardContent == .keep, forKey: "restoreClipboardAfterPaste")
        }
    }
    @Published var clipboardHistory: Bool { didSet { defaults.set(clipboardHistory, forKey: Keys.clipboardHistory) } }
    @Published var pasteResultText: Bool { didSet { defaults.set(pasteResultText, forKey: Keys.pasteResultText) } }
    @Published var holdShiftToAutoSend: Bool { didSet { defaults.set(holdShiftToAutoSend, forKey: Keys.holdShiftAutoSend) } }
    @Published var simulateKeypresses: Bool { didSet { defaults.set(simulateKeypresses, forKey: Keys.simulateKeypresses) } }
    @Published var showExperimentalModels: Bool { didSet { defaults.set(showExperimentalModels, forKey: Keys.experimentalModels) } }

    // Sound
    @Published var autoIncreaseMicVolume: Bool { didSet { defaults.set(autoIncreaseMicVolume, forKey: Keys.autoGain) } }
    @Published var silenceRemoval: Bool {
        didSet {
            defaults.set(silenceRemoval, forKey: Keys.silenceRemoval)
            defaults.set(silenceRemoval, forKey: "IsVADEnabled")
        }
    }
    @Published var dynamicNormalization: Bool { didSet { defaults.set(dynamicNormalization, forKey: Keys.dynamicNormalization) } }
    @Published var playbackWhenRecording: PlaybackWhenRecording {
        didSet {
            defaults.set(playbackWhenRecording.rawValue, forKey: Keys.playbackWhenRecording)
            defaults.set(playbackWhenRecording == .pause, forKey: "isPauseMediaEnabled")
            defaults.set(playbackWhenRecording == .mute, forKey: "isSystemMuteEnabled")
        }
    }
    @Published var soundEffects: SoundEffectsStyle {
        didSet {
            defaults.set(soundEffects.rawValue, forKey: Keys.soundEffects)
            defaults.set(soundEffects != .off, forKey: "isSoundFeedbackEnabled")
        }
    }
    @Published var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) } }

    // Home
    @Published var statsRange: StatsRange { didSet { defaults.set(statsRange.rawValue, forKey: Keys.statsRange) } }
    @Published var typingWordsPerMinute: Int { didSet { defaults.set(typingWordsPerMinute, forKey: Keys.typingWPM) } }

    // Agent plugins
    @Published var agentSound: Bool { didSet { defaults.set(agentSound, forKey: Keys.agentSound) } }
    @Published var agentAutoSend: Bool { didSet { defaults.set(agentAutoSend, forKey: Keys.agentAutoSend) } }
    @Published var claudeCodePluginInstalled: Bool { didSet { defaults.set(claudeCodePluginInstalled, forKey: Keys.claudePlugin) } }
    @Published var codexPluginInstalled: Bool { didSet { defaults.set(codexPluginInstalled, forKey: Keys.codexPlugin) } }

    private init() {
        let d = UserDefaults.standard
        let storedTheme = AppearanceTheme(rawValue: d.string(forKey: Keys.theme) ?? "") ?? .auto
        theme = storedTheme
        Self.applyAppearance(storedTheme)
        recordingWindowStyle = RecordingWindowStyle(rawValue: d.string(forKey: Keys.recordingWindowStyle) ?? "") ?? .classic
        alwaysShowMiniWindow = d.bool(forKey: Keys.alwaysShowMini)
        alwaysShowEdge = RecorderEdge(rawValue: d.string(forKey: Keys.alwaysShowEdge) ?? "") ?? .top
        automaticallyCheckForUpdates = d.object(forKey: Keys.autoUpdate) as? Bool ?? true
        errorLogging = d.bool(forKey: Keys.errorLogging)
        recordingRetention = RecordingRetention(rawValue: d.integer(forKey: Keys.recordingRetention)) ?? .forever
        startRecordingOnMenubarClick = d.bool(forKey: Keys.menubarClickRecords)
        alwaysClose = d.bool(forKey: Keys.alwaysClose)
        modelActiveDuration = ModelActiveDuration(rawValue: d.object(forKey: Keys.modelActiveDuration) as? Int ?? 60) ?? .oneMinute
        appFolderPath = d.string(forKey: Keys.appFolder) ?? SpeekSettings.defaultAppFolder.path
        clipboardContent = ClipboardContentPolicy(rawValue: d.string(forKey: Keys.clipboardContent) ?? "") ?? .keep
        clipboardHistory = d.bool(forKey: Keys.clipboardHistory)
        pasteResultText = d.object(forKey: Keys.pasteResultText) as? Bool ?? true
        holdShiftToAutoSend = d.bool(forKey: Keys.holdShiftAutoSend)
        simulateKeypresses = d.bool(forKey: Keys.simulateKeypresses)
        showExperimentalModels = d.bool(forKey: Keys.experimentalModels)
        autoIncreaseMicVolume = d.object(forKey: Keys.autoGain) as? Bool ?? true
        silenceRemoval = d.object(forKey: Keys.silenceRemoval) as? Bool ?? true
        dynamicNormalization = d.object(forKey: Keys.dynamicNormalization) as? Bool ?? true
        playbackWhenRecording = PlaybackWhenRecording(rawValue: d.string(forKey: Keys.playbackWhenRecording) ?? "") ?? .pause
        soundEffects = SoundEffectsStyle(rawValue: d.string(forKey: Keys.soundEffects) ?? "") ?? .classic
        soundVolume = d.object(forKey: Keys.soundVolume) as? Double ?? 1.0
        statsRange = StatsRange(rawValue: d.string(forKey: Keys.statsRange) ?? "") ?? .allTime
        typingWordsPerMinute = d.object(forKey: Keys.typingWPM) as? Int ?? 40
        agentSound = d.object(forKey: Keys.agentSound) as? Bool ?? true
        agentAutoSend = d.bool(forKey: Keys.agentAutoSend)
        claudeCodePluginInstalled = d.bool(forKey: Keys.claudePlugin)
        codexPluginInstalled = d.bool(forKey: Keys.codexPlugin)
    }

    static var defaultAppFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speek", isDirectory: true)
    }

    enum Keys {
        static let theme = "speek.theme"
        static let recordingWindowStyle = "speek.recordingWindowStyle"
        static let alwaysShowMini = "speek.alwaysShowMiniWindow"
        static let alwaysShowEdge = "speek.alwaysShowEdge"
        static let autoUpdate = "speek.autoUpdate"
        static let errorLogging = "speek.errorLogging"
        static let recordingRetention = "speek.recordingRetention"
        static let menubarClickRecords = "speek.menubarClickRecords"
        static let alwaysClose = "speek.alwaysClose"
        static let modelActiveDuration = "speek.modelActiveDuration"
        static let appFolder = "speek.appFolder"
        static let clipboardContent = "speek.clipboardContent"
        static let clipboardHistory = "speek.clipboardHistory"
        static let pasteResultText = "speek.pasteResultText"
        static let holdShiftAutoSend = "speek.holdShiftAutoSend"
        static let simulateKeypresses = "speek.simulateKeypresses"
        static let experimentalModels = "speek.experimentalModels"
        static let autoGain = "speek.autoGain"
        static let silenceRemoval = "speek.silenceRemoval"
        static let dynamicNormalization = "speek.dynamicNormalization"
        static let playbackWhenRecording = "speek.playbackWhenRecording"
        static let soundEffects = "speek.soundEffects"
        static let soundVolume = "speek.soundVolume"
        static let statsRange = "speek.statsRange"
        static let typingWPM = "speek.typingWPM"
        static let agentSound = "speek.agent.sound"
        static let agentAutoSend = "speek.agent.autoSend"
        static let claudePlugin = "speek.plugin.claude"
        static let codexPlugin = "speek.plugin.codex"
    }
}

extension Notification.Name {
    static let speekRecordingWindowStyleDidChange = Notification.Name("speek.recordingWindowStyleDidChange")
    static let speekNavigate = Notification.Name("speek.navigate")
    static let speekShowModeSwitcher = Notification.Name("speek.showModeSwitcher")
}
