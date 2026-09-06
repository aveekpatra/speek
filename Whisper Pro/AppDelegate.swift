import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager?.applyActivationPolicy()
        ModeSwitcherController.shared.start()
        #if DEBUG
        SnapshotTool.runIfRequested()
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = AgentUpdateCenter.shared.handle(url: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let menuBarManager = menuBarManager, !menuBarManager.isMenuBarOnly {
            if WindowManager.shared.showMainWindow() != nil {
                return false
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // llama.cpp's Metal backend aborts in its static destructors if a model is still
        // resident at exit; release it first.
        S1MiniService.shared.unloadSync()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
