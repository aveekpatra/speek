import Foundation
import AppKit
import ApplicationServices
import os

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(subsystem: "com.aveekpatra.speek", category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    private static let prePasteDelay: TimeInterval = 0.05
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    /// - Parameter targetConfirmed: result of `focusedElementLikelyEditable()` if the
    ///   caller already probed; nil probes here. When the target is not confirmed the
    ///   previous clipboard is always put back afterwards, so the user's clipboard is
    ///   not silently replaced by a transcript that may not have landed anywhere.
    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String, targetConfirmed: Bool? = nil) -> Task<PasteResult, Never> {
        Task { @MainActor in
            await performPasteSession(text, targetConfirmed: targetConfirmed)
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    /// Same as `pasteAtCursorAndWaitUntilPosted`; kept for callers that already know
    /// their target (an agent's terminal we just activated).
    @MainActor
    static func forcePasteAtCursor(_ text: String) async -> PasteResult {
        await performPasteSession(text)
    }

    @MainActor
    private static func performPasteSession(_ text: String, targetConfirmed: Bool? = nil) async -> PasteResult {
        let pasteboard = NSPasteboard.general

        // Always paste. The accessibility probe is advisory only: Firefox-based browsers
        // (Zen, Firefox) answer "the window is focused" while the caret sits in a text
        // box, and Electron apps answer nothing at all until their tree is switched on.
        // Gating Cmd+V on that answer is what made dictation land on the clipboard
        // instead of in Discord, Slack and the like. A Cmd+V that lands nowhere is
        // harmless; a transcript stranded on the clipboard is not.
        //
        // What the probe still decides: what happens to the clipboard afterwards. A
        // confirmed text target follows the "restore clipboard" setting. An unconfirmed
        // one always gets the previous clipboard back, and the recorder offers a Copy
        // button instead of replacing the clipboard behind the user's back.
        let targetIsKnownEditable = targetConfirmed ?? focusedElementLikelyEditable()
        let shouldRestoreClipboard = targetIsKnownEditable
            ? UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
            : true
        if !targetIsKnownEditable {
            logger.notice("Focused element not confirmed editable; pasting anyway and restoring the clipboard")
        }
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
        let sessionID = UUID().uuidString

        guard ClipboardManager.setClipboard(
            text,
            transient: shouldRestoreClipboard,
            sessionID: shouldRestoreClipboard ? sessionID : nil
        ) else {
            logger.error("Failed to prepare clipboard for paste")
            return .commandNotPosted
        }

        await wait(prePasteDelay)

        let pasteResult = await pasteFromClipboard()
        if shouldRestoreClipboard {
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                on: pasteboard
            )
        }

        return pasteResult
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard
    ) {
        let delay = max(
            UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
            minimumClipboardRestoreDelay
        )

        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID) else {
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText &&
            pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard() async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.error("Failed to create Cmd+V keyboard events")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vUp.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    // MARK: - Paste target detection

    /// Advisory: true when the focused element is confirmed as a text target (a text
    /// field or area, a settable value, or a readable selected-text range, which is
    /// how Slack, Discord and Gecko composers expose themselves). Never gates the
    /// paste itself; it only decides whether the previous clipboard is restored and
    /// whether the recorder offers a Copy button. Gecko browsers report the window as
    /// focused until their tree is up and Electron apps report nothing, so "unknown"
    /// is common and must not be treated as "nowhere to paste".
    @MainActor
    static func focusedElementLikelyEditable() -> Bool {
        guard AXIsProcessTrusted() else { return true } // can't detect → behave as before

        // Electron / Chromium apps (ChatGPT with Codex, Slack, VS Code, Cursor...) keep
        // their accessibility tree off until a client asks for it; until then every read
        // fails with kAXErrorCannotComplete. Asking the frontmost app to turn it on makes
        // the focused element readable from the next call on.
        var frontApp: AXUIElement?
        if let front = NSWorkspace.shared.frontmostApplication {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            frontApp = app
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        // The system-wide element often fails for Electron apps even once their tree is
        // on; asking the frontmost application directly still works.
        if status != .success, let frontApp {
            status = AXUIElementCopyAttributeValue(frontApp, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        }
        guard status == .success, let focused = focusedRef else {
            // Nothing readable in focus. That is not "nowhere": Electron apps with their
            // tree still off answer this way. The paste is attempted regardless; only
            // the clipboard restore and the Copy offer key off this answer.
            logger.notice("Focused element unknown (\(status.rawValue)); target unconfirmed")
            return false
        }
        var element = focused as! AXUIElement
        var role = axRole(of: element)

        // The window or application as "focus" means the app has not told us what is
        // inside. Look one level in; if nothing is there the target is unconfirmed.
        if role == kAXWindowRole as String || role == kAXApplicationRole as String {
            var inner: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &inner) == .success,
                  let innerElement = inner else {
                logger.notice("Focused element is the \(role, privacy: .public) with nothing inside; target unconfirmed")
                return false
            }
            element = innerElement as! AXUIElement
            role = axRole(of: element)
        }

        let confirmed = isTextTarget(element, role: role)
        if !confirmed {
            logger.notice("Focused element role \(role, privacy: .public) not confirmed as a text target")
        }
        return confirmed
    }

    private static func axRole(of element: AXUIElement) -> String {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        return (roleRef as? String) ?? ""
    }

    /// Confirmed text targets only: text fields and areas by role, anything whose
    /// value can be set (native editors), anything whose selected-text range can be
    /// set, or anything inside an editable ancestor (WebKit, Chromium and Gecko
    /// editors, which show up as AXTextArea or AXGroup once their tree is up). A
    /// merely readable selected-text range is not enough: the Finder desktop answers
    /// that with an empty range.
    private static func isTextTarget(_ element: AXUIElement, role: String) -> Bool {
        let textRoles: Set<String> = [
            kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String,
        ]
        if textRoles.contains(role) { return true }

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        settable = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }

        var namesRef: CFArray?
        if AXUIElementCopyAttributeNames(element, &namesRef) == .success,
           let names = namesRef as? [String], names.contains("AXEditableAncestor") {
            return true
        }
        return false
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: AutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags   = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags   = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
