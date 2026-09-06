import AppKit
import ApplicationServices
import os

/// Brings the window, tab, or pane an agent session runs in to the front.
enum TerminalLocator {
    private static let logger = Logger(subsystem: "com.aveekpatra.speek", category: "TerminalLocator")

    /// Runs on the main thread: AppKit activation and AppleScript want it, and the CLI
    /// calls it makes are short.
    static func focus(_ update: AgentUpdate) {
        // tmux first: the pane switch happens inside the terminal whatever app hosts it.
        if let pane = update.tmuxPane { selectTmuxPane(pane) }

        var handled = false
        switch update.terminalBundleID {
        case "com.apple.Terminal":
            if let tty = update.tty { handled = selectTerminalTab(tty: tty) }
        case "com.googlecode.iterm2":
            if let session = update.itermSession { handled = selectITermSession(session) }
        case "com.cmuxterm.app":
            if let target = update.cmuxTarget { handled = selectCmuxSurface(target) }
        case "com.openai.codex":
            // The Codex desktop app: its own "copy thread link" format is
            // codex://threads/<thread id>, and the hook's session id is that thread id.
            if !update.session.isEmpty, update.session != "preview",
               let url = URL(string: "codex://threads/\(update.session)") {
                NSWorkspace.shared.open(url)
                handled = true
            }
        case "com.anthropic.claudefordesktop":
            // The Claude desktop app opens a specific Code session through its own link,
            // but only by its host session id ("local_..."), which the hook captures from
            // CLAUDE_CODE_HOST_SESSION_ID. A bare Claude Code UUID is rejected by the app.
            if let host = update.hostSession, host.hasPrefix("local_"),
               let url = URL(string: "claude://code/continue?session=\(host)&source=speek") {
                NSWorkspace.shared.open(url)
                handled = true
            }
        default:
            break
        }

        guard let bundleID = update.terminalBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.error("No terminal app recorded for \(update.agent.displayName, privacy: .public)")
            return
        }
        // Cooperative activation (macOS 14+): when Speek itself is the active app, another
        // app only comes forward if Speek yields to it first.
        if NSApp.isActive { NSApp.yieldActivation(to: app) }
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        logger.notice("Focus \(bundleID, privacy: .public): specific=\(handled) activated=\(activated)")
        if !handled {
            // Generic apps: raise the window whose title mentions the project or branch.
            raiseWindow(of: app, matching: [update.projectName, update.branchName ?? ""].filter { !$0.isEmpty })
        }
    }

    // MARK: tmux

    private static func selectTmuxPane(_ pane: String) {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let tmux = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        for arguments in [["select-window", "-t", pane], ["select-pane", "-t", pane]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmux)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: cmux

    /// `target` is "workspace|panel|surface". Selecting the workspace switches the window
    /// and tab group; the panel and surface narrow it down to the exact pane.
    private static func selectCmuxSurface(_ target: String) -> Bool {
        let parts = target.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return false }
        let candidates = ["/opt/homebrew/bin/cmux", "/usr/local/bin/cmux", "/Applications/cmux.app/Contents/Resources/bin/cmux"]
        guard let cmux = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        let (workspace, panel, surface) = (parts[0], parts[1], parts[2])
        var commands: [[String]] = []
        if !workspace.isEmpty { commands.append(["select-workspace", "--workspace", workspace]) }
        if !panel.isEmpty { commands.append(["focus-panel", "--panel", panel]) }
        if !surface.isEmpty { commands.append(["tab-action", "--action", "focus", "--surface", surface]) }
        var ok = false
        for arguments in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmux)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if arguments[0] == "select-workspace", process.terminationStatus == 0 { ok = true }
        }
        return ok
    }

    // MARK: Terminal.app

    private static func selectTerminalTab(tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "/dev/\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScript(script)
    }

    // MARK: iTerm2

    private static func selectITermSession(_ sessionID: String) -> Bool {
        // ITERM_SESSION_ID looks like "w0t1p0:UUID"; the session id proper is the UUID.
        let id = sessionID.split(separator: ":").last.map(String.init) ?? sessionID
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "\(id)" then
                            select s
                            select t
                            select w
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.notice("AppleScript failed: \(error, privacy: .public)")
            return false
        }
        return result.booleanValue
    }

    // MARK: Accessibility fallback

    private static func raiseWindow(of app: NSRunningApplication, matching needles: [String]) {
        guard AXIsProcessTrusted(), !needles.isEmpty else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String else { continue }
            if needles.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                return
            }
        }
    }
}
