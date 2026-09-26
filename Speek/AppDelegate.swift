import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?
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
        SpeekMainWindow.shared.show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SpeekMainWindow.shared.show()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        TaskScheduler.shared.stop()
        CodingTaskManager.shared.cancelAll()
        AssistantController.shared.stopPresentation()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
