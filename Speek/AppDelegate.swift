import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Take speek:// URLs before SwiftUI does: its window scene would otherwise
        // present a main window for every URL, which drags the user to another Space.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager?.applyActivationPolicy()
        ModeSwitcherController.shared.start()
        AgentEventListener.shared.start()
        #if DEBUG
        SnapshotTool.runIfRequested()
        #endif
    }

    /// Set whenever a speek:// URL arrives; a "reopen" that Launch Services sends along
    /// with it must not re-show the main window.
    private var lastURLOpen = Date.distantPast

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        lastURLOpen = Date()
        MainActor.assumeIsolated {
            _ = AgentUpdateCenter.shared.handle(url: url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        lastURLOpen = Date()
        for url in urls {
            _ = AgentUpdateCenter.shared.handle(url: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if Date().timeIntervalSince(lastURLOpen) < 1.5 { return false }
        // A real reopen (Dock click, `open -a Speek`): show the main window right away,
        // so SwiftUI sees a visible window and does not present a second one.
        return WindowManager.shared.showMainWindow() == nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        // llama.cpp's Metal backend aborts in its static destructors if a model is still
        // resident at exit; release it first.
        S1MiniService.shared.unloadSync()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Window-closing utilities send a Quit Apple event a moment after the last window
    /// closes. While Speek runs in the menu bar that quit is refused, unless it comes from
    /// the system itself (logout, shutdown), the Dock, or Activity Monitor. Quit from
    /// Speek's own menu bar item calls terminate directly and is never affected.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard sender.activationPolicy() == .accessory,
              SpeekSettings.shared.keepRunningInMenuBar,
              let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication) else { return .terminateNow }
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value ?? 0
        let senderBundle = NSRunningApplication(processIdentifier: senderPID)?.bundleIdentifier ?? ""
        let allowed = ["com.apple.loginwindow", "com.apple.dock", "com.apple.ActivityMonitor", "com.apple.finder"]
        if senderPID == 0 || allowed.contains(senderBundle) { return .terminateNow }
        NSLog("Speek: ignoring a Quit event from %@ (pid %d) while running in the menu bar", senderBundle, senderPID)
        return .terminateCancel
    }
}
