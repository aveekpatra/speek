import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog
import AppIntents
import FluidAudio

@main
struct SpeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer

    @StateObject private var engine: SpeekEngine
    @StateObject private var whisperModelManager: WhisperModelManager
    @StateObject private var fluidAudioModelManager: FluidAudioModelManager
    @StateObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var recorderUIManager: RecorderUIManager
    @StateObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = false
    @State private var showMenuBarIcon = true
    @State private var didShowAccessibilityReminder = false

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService

    init() {
        // Disable HTTP response caching — prevents API responses from being stored in Cache.db
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()
        WaveformStyleMigration.prepareIfNeeded()

        let logger = Logger(subsystem: "com.aveekpatra.speek", category: "Initialization")
        // Keep existing model order stable; append new models after synced entities.
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            SessionMetric.self,
            CoachNote.self,
            TypedDailyMetric.self,
            ProcessedLog.self,
            TypedPromptSignature.self
        ])
        let resolvedContainer: ModelContainer

        // Attempt 1: Try persistent storage
        do {
            resolvedContainer = try Self.createPersistentContainer(schema: schema, logger: logger)
        } catch let persistentError {
            // Attempt 2: Try in-memory storage
            do {
                resolvedContainer = try Self.createInMemoryContainer(schema: schema, logger: logger)
                logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Storage Warning")
                    alert.informativeText = String(localized: "Speek couldn't access its storage location. Your transcriptions will not be saved between sessions.")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: String(localized: "OK"))
                    alert.runModal()
                }
            } catch let memoryError {
                let persistentDetail = Self.fullErrorDescription(persistentError)
                let memoryDetail = Self.fullErrorDescription(memoryError)
                logger.critical("❌ All ModelContainer init attempts failed.\nPersistent:\n\(persistentDetail, privacy: .public)\nIn-memory:\n\(memoryDetail, privacy: .public)")
                fatalError("Speek failed to initialize storage.\nPersistent:\n\(persistentDetail)\nIn-memory:\n\(memoryDetail)")
            }
        }

        container = resolvedContainer
        DictionaryService.removeExactDuplicateContent(context: resolvedContainer.mainContext, source: "launch")

        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        aiService.refreshOllamaAvailabilityInBackground()

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: resolvedContainer.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)


        // 1. Create modelsDirectory URL
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek")
        let modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")

        // 2. Create model managers
        let whisperModelManager = WhisperModelManager(modelsDirectory: modelsDirectory)
        let fluidAudioModelManager = FluidAudioModelManager()
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )

        // 3. Create UI manager
        let recorderUIManager = RecorderUIManager()

        // 4. Create engine
        let engine = SpeekEngine(
            modelContext: resolvedContainer.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            enhancementService: enhancementService
        )

        // 5. Configure circular deps
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
        engine.recorderUIManager = recorderUIManager

        // 6. Initialize model state
        // Migration and refreshAllAvailableModels must run before loadCurrentTranscriptionModel so renamed keys are remapped and imported models are present when restoring the saved selection.
        StreamingKeysMigration.run()
        whisperModelManager.createModelsDirectoryIfNeeded()
        whisperModelManager.loadAvailableModels()
        transcriptionModelManager.refreshAllAvailableModels()
        // ModeManager.shared must be touched before loadCurrentTranscriptionModel(): its init
        // runs a one-time migration that copies any mode-pinned transcription model into
        // "CurrentTranscriptionModel" so the global AI Models selection becomes authoritative.
        _ = ModeManager.shared
        transcriptionModelManager.loadCurrentTranscriptionModel()

        _whisperModelManager = StateObject(wrappedValue: whisperModelManager)
        _fluidAudioModelManager = StateObject(wrappedValue: fluidAudioModelManager)
        _transcriptionModelManager = StateObject(wrappedValue: transcriptionModelManager)
        _recorderUIManager = StateObject(wrappedValue: recorderUIManager)
        _engine = StateObject(wrappedValue: engine)
        #if DEBUG
        SnapshotTool.engine = engine
        #endif

        // 7. Create other services that depend on engine
        let recordingShortcutManager = RecordingShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        _recordingShortcutManager = StateObject(wrappedValue: recordingShortcutManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: resolvedContainer, engine: engine)

        let activeWindowService = ActiveWindowService.shared
        _activeWindowService = StateObject(wrappedValue: activeWindowService)

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager,
            modelContext: resolvedContainer.mainContext
        )
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()

        let migrationTask = SessionMetricMigrationService.shared.runIfNeeded(modelContainer: resolvedContainer)
        let mainContext = resolvedContainer.mainContext
        Task {
            await migrationTask?.value
            TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: mainContext)
        }

        // The gray "Napsáno" line aggregates typed words from the Claude + Codex chat
        // logs (~4 GB across thousands of files). Scanning that at launch competed with
        // the dictation pipeline for CPU and the shared SwiftData store, making the whole
        // app feel laggy. It now runs lazily when the Dashboard appears (see
        // DashboardContent.task) — off the launch and dictation paths entirely.
    }

    // MARK: - Container Creation Helpers

    private static func fullErrorDescription(_ error: Error, depth: Int = 0) -> String {
        let ns = error as NSError
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        lines.append("\(indent)[\(ns.domain) \(ns.code)] \(ns.localizedDescription)")
        for (key, value) in ns.userInfo {
            let keyStr = "\(key)"
            if keyStr == NSUnderlyingErrorKey || keyStr == "NSDetailedErrors" { continue }
            lines.append("\(indent)  \(keyStr): \(value)")
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            lines.append("\(indent)  Underlying:")
            lines.append(fullErrorDescription(underlying, depth: depth + 2))
        }
        if let details = ns.userInfo["NSDetailedErrors"] as? [Error] {
            lines.append("\(indent)  DetailedErrors (\(details.count)):")
            for (i, detail) in details.enumerated() {
                lines.append("\(indent)    [\(i)]:")
                lines.append(fullErrorDescription(detail, depth: depth + 3))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func createPersistentContainer(schema: Schema, logger: Logger) throws -> ModelContainer {
        // Data lives under the Speek identifier — same folder as Recordings/ and
        // WhisperModels/. The old VoiceInk folder was a leftover from the rename and
        // pointing the stores there orphaned the real transcript/dictionary/stats history.
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.aveekpatra.speek", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
        let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")
        let statsStoreURL = appSupportURL.appendingPathComponent("stats.store")
        let coachStoreURL = appSupportURL.appendingPathComponent("coach.store")
        // Derived chat-log metrics are safe to rebuild. Keep them in their own v2 store
        // so old experimental/corrupt typed stores never block app launch or dictation.
        let typedStoreURL = appSupportURL.appendingPathComponent("typed-v2.store")

        let transcriptSchema = Schema([Transcription.self])
        let transcriptConfig = ModelConfiguration(
            "default",
            schema: transcriptSchema,
            url: defaultStoreURL,
            cloudKitDatabase: .none
        )

        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        // Local-only: no CloudKit / iCloud sync. Dictionary stays on-device like the
        // transcript and stats stores. (Avoids CloudKit mirroring crash on unsigned builds.)
        let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
        let dictionaryConfig = ModelConfiguration(
            "dictionary",
            schema: dictionarySchema,
            url: dictionaryStoreURL,
            cloudKitDatabase: dictionaryCloudKit
        )

        let statsSchema = Schema([SessionMetric.self])
        let statsConfig = ModelConfiguration(
            "stats",
            schema: statsSchema,
            url: statsStoreURL,
            cloudKitDatabase: .none
        )

        let coachSchema = Schema([CoachNote.self])
        let coachConfig = ModelConfiguration(
            "coach",
            schema: coachSchema,
            url: coachStoreURL,
            cloudKitDatabase: .none
        )

        let typedSchema = Schema([TypedDailyMetric.self, ProcessedLog.self, TypedPromptSignature.self])
        let typedConfig = ModelConfiguration(
            "typed",
            schema: typedSchema,
            url: typedStoreURL,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig, statsConfig, coachConfig, typedConfig)
        } catch {
            logger.error("❌ Failed to create persistent ModelContainer:\n\(Self.fullErrorDescription(error), privacy: .public)")
            throw error
        }
    }

    private static func createInMemoryContainer(schema: Schema, logger: Logger) throws -> ModelContainer {
        let transcriptSchema = Schema([Transcription.self])
        let transcriptConfig = ModelConfiguration("default", schema: transcriptSchema, isStoredInMemoryOnly: true)

        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        let dictionaryConfig = ModelConfiguration("dictionary", schema: dictionarySchema, isStoredInMemoryOnly: true)

        let statsSchema = Schema([SessionMetric.self])
        let statsConfig = ModelConfiguration("stats", schema: statsSchema, isStoredInMemoryOnly: true)

        let coachSchema = Schema([CoachNote.self])
        let coachConfig = ModelConfiguration("coach", schema: coachSchema, isStoredInMemoryOnly: true)

        let typedSchema = Schema([TypedDailyMetric.self, ProcessedLog.self, TypedPromptSignature.self])
        let typedConfig = ModelConfiguration("typed", schema: typedSchema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig, statsConfig, coachConfig, typedConfig)
        } catch {
            logger.error("❌ Failed to create in-memory ModelContainer:\n\(Self.fullErrorDescription(error), privacy: .public)")
            throw error
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboardingV2 {
                    MainWindowView()
                        .environmentObject(engine)
                        .environmentObject(whisperModelManager)
                        .environmentObject(fluidAudioModelManager)
                        .environmentObject(transcriptionModelManager)
                        .environmentObject(recorderUIManager)
                        .environmentObject(recordingShortcutManager)
                        .environmentObject(updaterViewModel)
                        .environmentObject(menuBarManager)
                        .environmentObject(aiService)
                        .environmentObject(enhancementService)
                        .environmentObject(ThemeManager.shared)
                        .modelContainer(container)
                        .onAppear {
                            showAccessibilityReminderIfNeeded()

                            // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                            if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                                audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                            }
                        }
                        .background(WindowAccessor { window in
                            WindowManager.shared.configureWindow(window)
                        })
                        .onDisappear {
                            whisperModelManager.unloadModel()

                            // Stop the automatic audio cleanup process
                            audioCleanupManager.stopAutomaticCleanup()
                        }
                } else {
                    SpeekOnboardingView(hasCompleted: $hasCompletedOnboardingV2)
                        .environmentObject(fluidAudioModelManager)
                        .environmentObject(transcriptionModelManager)
                        .background(WindowAccessor { window in
                            WindowManager.shared.configureWindow(window)
                        })
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(recordingShortcutManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            Image(systemName: engine.recordingState == .recording ? "waveform.badge.mic" : "waveform")
        }
        .menuBarExtraStyle(.menu)

        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }


    private func showAccessibilityReminderIfNeeded() {
        #if LOCAL_BUILD
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return
        #else
        guard !didShowAccessibilityReminder else { return }
        didShowAccessibilityReminder = true

        guard !AXIsProcessTrusted() else { return }

        NotificationManager.shared.showNotification(
            title: String(localized: "Accessibility permission is not provided"),
            type: .warning,
            duration: 7.0,
            // Reset over "Open Settings": the usual stuck state is a stale TCC entry that
            // opening Settings alone cannot fix. Reset drops it and re-prompts.
            actionButton: (String(localized: "Reset permission"), {
                Task { @MainActor in
                    AccessibilityRepair.resetAndReprompt {
                        AccessibilityRepair.prompt()
                        AccessibilityRepair.openSettings()
                    }
                }
            })
        )
        #endif
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
