import AppKit
import ApplicationServices

/// Drops our stale Accessibility TCC entry and re-prompts. macOS keeps the grant tied to the
/// exact code signature it saw when the entry was created, so a rebuilt or replaced app keeps
/// a switch that is on but points at an older copy, and toggling it does nothing. Removing our
/// entry lets the next prompt re-create it against the current signature. Shared by onboarding
/// and the post-onboarding dashboard reminder so both offer the real fix, not just a link to
/// System Settings (which is the original dead end).
enum AccessibilityRepair {
    /// Resets the entry off the main thread (a stalled tccutil must never freeze the UI), then
    /// runs `then` back on the main actor (re-prompt, refresh status, open Settings, etc.).
    @MainActor
    static func resetAndReprompt(then: @escaping @MainActor () -> Void) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task {
            await resetEntry(bundleID: bundleID)
            then()
        }
    }

    /// Fires the standard Accessibility prompt, which re-creates the entry against the current
    /// code signature after a reset.
    @MainActor
    static func prompt() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }

    /// Selects the running app bundle in Finder so it can be dragged into the
    /// Accessibility list by hand (the reliable fallback when the entry is missing).
    @MainActor
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// True when the app runs from /Applications (or the user's Applications folder).
    static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix("\(home)/Applications/")
    }

    /// Installs a first copy at a stable path. Existing installations are never overwritten.
    @MainActor
    static func moveToApplicationsAndRelaunch() -> Bool {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications/Speek.app")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            return false
        }
        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([source])
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    /// Opens the Accessibility pane in System Settings.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func resetEntry(bundleID: String) async {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // tccutil is missing or refused: fall through to the prompt, no worse than before.
            }
        }.value
    }
}
