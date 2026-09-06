import SwiftUI
import AppKit
import OSLog

extension Notification.Name {
    static let mainWindowVisibilityChanged = Notification.Name("mainWindowVisibilityChanged")
}

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.aveekpatra.speek.mainWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("SpeekMainWindowFrame")

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "WindowManager")
    private weak var mainWindow: NSWindow?
    private var didApplyInitialPlacement = false

    private override init() {
        super.init()
    }
    
    func configureWindow(_ window: NSWindow) {
        if let existingWindow = mainWindow, existingWindow != window, existingWindow.isVisible {
            logger.notice("configureWindow: duplicate detected, reusing existing window")
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        logger.notice("configureWindow: registering main window")
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.title = "Speek"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 0, height: 0)
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        applyInitialPlacementIfNeeded(to: window)
        registerMainWindowIfNeeded(window)
        window.orderFrontRegardless()
    }
    
    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        // Do not overwrite window.identifier: SwiftUI uses it for state restoration and
        // will refuse to open the window on the next launch if it is unknown.
        window.delegate = self
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowOcclusionStateChanged(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }

    @objc private func mainWindowOcclusionStateChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let visible = window.isVisible && window.occlusionState.contains(.visible)
        NotificationCenter.default.post(name: .mainWindowVisibilityChanged, object: nil, userInfo: ["visible": visible])
    }
    
    func showMainWindow() -> NSWindow? {
        guard let window = resolveMainWindow() else {
            return nil
        }
        // Back to a regular app (Dock icon) unless the user chose menu bar only.
        if !UserDefaults.standard.bool(forKey: "IsMenuBarOnly"),
           NSApplication.shared.activationPolicy() != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .mainWindowVisibilityChanged, object: nil, userInfo: ["visible": true])
        return window
    }

    func hideMainWindow() {
        guard let window = resolveMainWindow() else {
            return
        }
        window.orderOut(nil)
        NotificationCenter.default.post(name: .mainWindowVisibilityChanged, object: nil, userInfo: ["visible": false])
    }
    
    func currentMainWindow() -> NSWindow? {
        resolveMainWindow()
    }
    
    private func registerMainWindowIfNeeded(_ window: NSWindow) {
        if mainWindow !== window {
            registerMainWindow(window)
        }
    }

    /// The SwiftUI-created main content window: titled, resizable, not a floating panel.
    private static func isMainCandidate(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled)
            && window.styleMask.contains(.resizable)
            && !window.styleMask.contains(.nonactivatingPanel)
            && !(window is NSPanel)
            && window.level == .normal
    }
    
    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }
        // Attempt to restore previous frame if one exists; otherwise fall back to a centered placement
        if !window.setFrameUsingName(Self.mainWindowAutosaveName) {
            window.center()
        }
        didApplyInitialPlacement = true
    }
    
    private func resolveMainWindow() -> NSWindow? {
        if let window = mainWindow {
            return window
        }

        logger.notice("resolveMainWindow: weak ref is nil, searching \(NSApplication.shared.windows.count, privacy: .public) windows by identifier")

        if let window = NSApplication.shared.windows.first(where: { Self.isMainCandidate($0) }) {
            logger.notice("resolveMainWindow: recovered window via style fallback")
            mainWindow = window
            window.delegate = self
            return window
        }

        let windowIDs = NSApplication.shared.windows.map { $0.identifier?.rawValue ?? "nil" }.joined(separator: ", ")
        logger.error("resolveMainWindow: FAILED — no window found with main identifier. Total windows: \(NSApplication.shared.windows.count, privacy: .public), identifiers: \(windowIDs, privacy: .public)")
        return nil
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === mainWindow {
            logger.notice("windowWillClose: main window closing, clearing weak reference")
            // Become a menu bar app right away. Utilities like SwiftQuit kill regular apps
            // whose last window closes; an accessory app (no Dock icon) is left alone, and
            // Speek keeps recording, pasting and answering agents from the menu bar.
            NSApplication.shared.setActivationPolicy(.accessory)
            window.orderOut(nil)
            NotificationCenter.default.post(name: .mainWindowVisibilityChanged, object: nil, userInfo: ["visible": false])
            mainWindow = nil
            didApplyInitialPlacement = false
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindow else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
} 
