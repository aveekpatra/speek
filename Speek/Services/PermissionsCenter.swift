import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI
import os

/// One place that knows the state of the two permissions Speek cannot work without
/// and how to get each of them with the fewest clicks macOS allows:
/// - Microphone: the system "Allow" dialog when it has never been asked; the
///   Microphone pane in System Settings when it was denied.
/// - Accessibility: macOS never lets an app grant this itself. The best path is the
///   system prompt (which lists Speek in the Accessibility pane) plus opening that
///   pane, so the user flips one switch. When Speek was trusted before and is not
///   now (a rebuilt copy: macOS ties the grant to the code signature), the stale
///   entry is dropped first, otherwise the switch shows "on" and does nothing.
@MainActor
final class PermissionsCenter: ObservableObject {
    static let shared = PermissionsCenter()

    @Published private(set) var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var isRepairingAccessibility = false

    var microphoneGranted: Bool { microphoneStatus == .authorized }
    var allGranted: Bool { microphoneGranted && accessibilityTrusted }

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "Permissions")
    private let wasTrustedKey = "speek.accessibilityWasGranted"
    private var guideWindow: NSWindow?
    private var pollTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    private init() {
        refresh()
    }

    func refresh() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = AXIsProcessTrusted()
        if accessibilityTrusted {
            UserDefaults.standard.set(true, forKey: wasTrustedKey)
        }
    }

    // MARK: Actions

    /// Microphone with the fewest clicks: the system dialog when never asked, the
    /// Settings pane when it was denied (macOS shows no second dialog).
    func allowMicrophone() {
        refresh()
        switch microphoneStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        case .authorized:
            return
        default:
            openMicrophoneSettings()
        }
    }

    /// Accessibility with the fewest clicks: drop a stale entry if this copy used to
    /// be trusted, fire the system prompt (it adds Speek to the list), open the pane.
    func allowAccessibility() {
        refresh()
        guard !accessibilityTrusted else { return }
        let wasTrusted = UserDefaults.standard.bool(forKey: wasTrustedKey)
        if wasTrusted, !isRepairingAccessibility {
            isRepairingAccessibility = true
            logger.notice("Accessibility was granted before; dropping the stale entry before asking again")
            AccessibilityRepair.resetAndReprompt { [weak self] in
                self?.isRepairingAccessibility = false
                AccessibilityRepair.prompt()
                AccessibilityRepair.openSettings()
            }
        } else {
            AccessibilityRepair.prompt()
            AccessibilityRepair.openSettings()
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Guide window

    /// Shows the guide when something is missing. Safe to call on every launch.
    func showGuideIfNeeded() {
        refresh()
        guard !allGranted else { return }
        showGuide()
    }

    func showGuide() {
        refresh()
        if let guideWindow {
            guideWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: PermissionsGuideView(center: self))
        let window = NSWindow(contentViewController: host)
        window.title = "Permissions"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setContentSize(host.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guideWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.guideDidClose() }
        }
        startPolling()
    }

    func closeGuide() {
        guideWindow?.close()
    }

    private func guideDidClose() {
        guideWindow = nil
        pollTask?.cancel()
        pollTask = nil
        closeTask?.cancel()
        closeTask = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                if self.allGranted, self.closeTask == nil {
                    // Give the checkmarks a moment to show, then get out of the way.
                    self.closeTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        self?.closeGuide()
                    }
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }
}
