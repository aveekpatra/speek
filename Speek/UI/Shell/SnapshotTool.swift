import AppKit
import SwiftUI
import ScreenCaptureKit

#if DEBUG
/// Developer aid: `Speek.app/Contents/MacOS/Speek -speekSnapshot /tmp/shots [-speekSnapshotPages home,modes]`
/// opens each page, writes `<page>.png` rendered from the window's own view hierarchy,
/// and quits. Needs no screen-recording permission because it never reads the screen.
@MainActor
enum SnapshotTool {
    /// Set by the app at launch so dev options can drive the engine.
    static weak var engine: SpeekEngine?

    /// `-speekInstallAgent claude|codex|all`: install agent hooks without the UI, then exit.
    static func runAgentInstallIfRequested(_ defaults: UserDefaults) {
        guard let which = defaults.string(forKey: "speekInstallAgent"), !which.isEmpty else { return }
        let plugins: [AgentPlugin] = which == "all" ? AgentPlugin.allCases : (which == "codex" ? [.codex] : [.claudeCode])
        for plugin in plugins {
            do { try AgentHookInstaller.install(plugin); print("installed \(plugin.displayName)") }
            catch { print("install \(plugin.displayName) failed: \(error.localizedDescription)") }
        }
        exit(0)
    }

    static func runIfRequested() {
        let defaults = UserDefaults.standard
        runAgentInstallIfRequested(defaults)
        applyDevLaunchOptions(defaults)
        runTranscriptionTestIfRequested(defaults)
        runS1TestIfRequested(defaults)
        guard let directory = defaults.string(forKey: "speekSnapshot"), !directory.isEmpty else { return }
        let requested = defaults.string(forKey: "speekSnapshotPages")?
            .split(separator: ",")
            .compactMap { SpeekPage(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        let pages = (requested?.isEmpty == false) ? requested! : SpeekPage.allCases
        let extraDelay = defaults.double(forKey: "speekSnapshotDelay")

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5 + extraDelay))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for page in pages {
                SpeekNavigation.shared.open(page)
                try? await Task.sleep(for: .seconds(0.9))
                if let window = mainWindow() {
                    capture(window: window, to: url.appendingPathComponent("\(page.rawValue).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// `-speekPage modes` opens a page; `-speekWindowFrame x,y,w,h` positions the main
    /// window (AppKit coordinates, origin bottom-left). Used to inspect the UI while
    /// another app stays frontmost.
    static func applyDevLaunchOptions(_ defaults: UserDefaults) {
        let page = defaults.string(forKey: "speekPage").flatMap { SpeekPage(rawValue: $0) }
        let frameString = defaults.string(forKey: "speekWindowFrame")
        guard page != nil || frameString != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            if let page { SpeekNavigation.shared.open(page) }
            for window in NSApp.windows where window.isVisible {
                NSLog("SpeekDev window: %@ frame=%@", String(describing: type(of: window)), NSStringFromRect(window.frame))
            }
            if let frameString {
                let parts = frameString.split(separator: ",").compactMap { Double($0) }
                if parts.count == 4, let window = mainWindow() {
                    window.setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: true)
                }
            }
        }
    }

    /// `-speekTranscribeFile /path/audio.aiff [-speekTranscribeModel name]` transcribes a
    /// file with the named (or current) model and logs the text.
    static func runTranscriptionTestIfRequested(_ defaults: UserDefaults) {
        if let text = defaults.string(forKey: "speekEnhanceOnly"), !text.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard let engine, let enhancementService = engine.getEnhancementService(), let aiService = enhancementService.getAIService() else { return }
                var mode = ModeManager.shared.currentEffectiveConfiguration ?? ModeConfig(name: "Test", isAIEnhancementEnabled: true)
                mode.isAIEnhancementEnabled = true
                mode.selectedAIProvider = AIProvider.s1Mini.rawValue
                mode.selectedAIModel = "S1-mini"
                mode.selectedPrompt = PromptTemplates.chatPromptId.uuidString
                mode.s1Styling = "casual"
                let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(mode: mode, enhancementService: enhancementService, aiService: aiService)
                NSLog("SpeekDev: enhancement configured=%d provider=%@ prompt=%@", enhancementService.isConfigured(for: configuration) ? 1 : 0, configuration.provider?.rawValue ?? "nil", configuration.prompt?.title ?? "nil")
                do {
                    let (enhanced, duration, _) = try await enhancementService.enhance(text, configuration: configuration)
                    NSLog("SpeekDev: ENHANCED (%.1fs): %@", duration, enhanced)
                } catch {
                    NSLog("SpeekDev: enhancement failed: %@", String(describing: error))
                }
            }
            return
        }
        guard let path = defaults.string(forKey: "speekTranscribeFile"), !path.isEmpty else { return }
        let modelName = defaults.string(forKey: "speekTranscribeModel")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let engine else { NSLog("SpeekDev: engine unavailable"); return }
            let manager = engine.transcriptionModelManager
            let model = manager.allAvailableModels.first { $0.name == modelName } ?? manager.currentTranscriptionModel
            guard let model else { NSLog("SpeekDev: no model"); return }
            NSLog("SpeekDev: transcribing %@ with %@", path, model.displayName)
            for pass in 1...3 {
                let start = Date()
                do {
                    let text = try await engine.serviceRegistry.transcribe(
                        audioURL: URL(fileURLWithPath: path),
                        model: model,
                        context: TranscriptionRequestContext(language: "en", prompt: nil)
                    )
                    NSLog("SpeekDev: RESULT pass %d (%.1fs): %@", pass, Date().timeIntervalSince(start), text)
                    if pass == 1, defaults.bool(forKey: "speekEnhanceTest"),
                       let enhancementService = engine.getEnhancementService(),
                       let aiService = enhancementService.getAIService() {
                        var mode = ModeManager.shared.currentEffectiveConfiguration ?? ModeConfig(name: "Test", isAIEnhancementEnabled: true)
                        mode.isAIEnhancementEnabled = true
                        mode.selectedAIProvider = AIProvider.s1Mini.rawValue
                        mode.selectedAIModel = "S1-mini"
                        mode.selectedPrompt = PromptTemplates.chatPromptId.uuidString
                        mode.s1Styling = "casual"
                        let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(mode: mode, enhancementService: enhancementService, aiService: aiService)
                        NSLog("SpeekDev: enhancement configured=%d provider=%@ model=%@", enhancementService.isConfigured(for: configuration) ? 1 : 0, configuration.provider?.rawValue ?? "nil", configuration.modelName ?? "nil")
                        do {
                            let (enhanced, duration, _) = try await enhancementService.enhance(text, configuration: configuration)
                            NSLog("SpeekDev: ENHANCED (%.1fs): %@", duration, enhanced)
                        } catch {
                            NSLog("SpeekDev: enhancement failed: %@", String(describing: error))
                        }
                    }
                } catch {
                    NSLog("SpeekDev: transcription failed: %@", String(describing: error))
                }
            }
        }
    }

    /// `-speekS1Test "raw transcript"` downloads S1-mini if needed and logs the cleaned text.
    static func runS1TestIfRequested(_ defaults: UserDefaults) {
        guard let text = defaults.string(forKey: "speekS1Test"), !text.isEmpty else { return }
        Task { @MainActor in
            if !S1MiniModelManager.shared.isDownloaded {
                S1MiniModelManager.shared.download()
                while !S1MiniModelManager.shared.isDownloaded {
                    try? await Task.sleep(for: .seconds(2))
                    if let status = S1MiniModelManager.shared.downloadStatus { NSLog("SpeekDev: %@", status.message) }
                }
            }
            let start = Date()
            do {
                let result = try await S1MiniService.shared.normalize(text, styling: .semiCasual, structure: .prose, context: .general)
                NSLog("SpeekDev: S1 RESULT (%.1fs): %@", Date().timeIntervalSince(start), result)
                let start2 = Date()
                let result2 = try await S1MiniService.shared.normalize(text, styling: .formal, structure: .lists, context: .email)
                NSLog("SpeekDev: S1 RESULT formal/lists (%.1fs): %@", Date().timeIntervalSince(start2), result2)
            } catch {
                NSLog("SpeekDev: S1 failed: %@", String(describing: error))
            }
        }
    }

    static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !$0.styleMask.contains(.nonactivatingPanel) }
    }

    static func capture(window: NSWindow, to url: URL) {
        let windowID = CGWindowID(window.windowNumber)
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    NSLog("SnapshotTool: window \(windowID) not in shareable content")
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = Int(scWindow.frame.width * 2)
                config.height = Int(scWindow.frame.height * 2)
                config.showsCursor = false
                config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: url)
                }
            } catch {
                NSLog("SnapshotTool: capture failed: \(error)")
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        // Fallback: render the layer tree (glass may be missing, but layout is visible).
        if !FileManager.default.fileExists(atPath: url.path), let view = window.contentView, let layer = view.layer {
            let scale = window.backingScaleFactor
            let size = view.bounds.size
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            layer.render(in: context.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }

    /// Capture an arbitrary window (e.g. the recorder panel) by title match.
    static func capturePanel(named title: String, to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.title == title || String(describing: type(of: $0)).contains(title) }) else { return }
        capture(window: window, to: url)
    }
}
#endif
