import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?
    /// Set whenever a speek:// URL arrives; the "reopen" Launch Services sends with it must not show the window.
    private var lastURLOpen = Date.distantPast

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["isPauseMediaEnabled": true])
        // Take speek:// URLs (coding assistant hooks) before SwiftUI can open a window for them.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:with:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        lastURLOpen = Date()
        MainActor.assumeIsolated { _ = AgentUpdateCenter.shared.handle(url: url) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        lastURLOpen = Date()
        for url in urls { _ = AgentUpdateCenter.shared.handle(url: url) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "speek.models.september2026") {
            for (key, old, new) in [
                ("speek.actions.openRouterRoutingModel", "openai/gpt-4o-mini", "openai/gpt-6-luna"),
                ("speek.actions.openRouterSpeechModel", "openai/whisper-1", "openai/gpt-transcribe"),
                ("speek.actions.openRouterVoiceModel", "microsoft/mai-voice-2", "microsoft/mai-voice-2-flash")
            ] {
                if defaults.string(forKey: key) == nil || defaults.string(forKey: key) == old { defaults.set(new, forKey: key) }
            }
            defaults.set(true, forKey: "speek.models.september2026")
        }
        AssistantController.shared.start(showControl: true)
        AgentEventListener.shared.start()
        SpeekMainWindow.shared.show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Date().timeIntervalSince(lastURLOpen) < 1.5 { return false }
        SpeekMainWindow.shared.show()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        TaskScheduler.shared.stop()
        AssistantController.shared.stopPresentation()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
