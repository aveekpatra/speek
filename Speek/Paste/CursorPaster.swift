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

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<PasteResult, Never> {
        Task { @MainActor in
            await performPasteSession(text)
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    private static func performPasteSession(_ text: String) async -> PasteResult {
        let pasteboard = NSPasteboard.general

        // No editable target to paste into: don't fire ⌘V (which makes macOS beep
        // and, with clipboard-restore on, would also drop the text). Instead just
        // leave the transcript on the clipboard so it can be pasted later with ⌘V.
        if !focusedElementLikelyEditable() {
            // transient: true tags the dictated text as auto-generated/transient
            // (org.nspasteboard) so clipboard managers like Maccy/Raycast don't
            // permanently store it — it stays pasteable via ⌘V either way.
            _ = ClipboardManager.setClipboard(text, transient: true, sessionID: nil)
            NotificationManager.shared.showNotification(
                title: String(localized: "Copied to clipboard — paste anywhere with ⌘V"),
                type: .success
            )
            return .commandNotPosted
        }

        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
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

    /// True when the system-wide focused element can accept pasted text (a text
    /// field/area, combo box, or anything with a settable value — covers most web
    /// editors). When nothing is focused or the focus is non-editable, returns
    /// false so the caller copies to the clipboard instead of pasting.
    ///
    /// Exposed (not `private`) so callers can decide up front whether a paste will
    /// land in an editable field — e.g. the recorder panel uses this to know
    /// whether to dismiss immediately or show a "⌘V to paste" hint first.
    @MainActor
    static func focusedElementLikelyEditable() -> Bool {
        guard AXIsProcessTrusted() else { return true } // can't detect → behave as before

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard status == .success, let focused = focusedRef else {
            return false // nothing focused → nowhere to paste
        }
        let element = focused as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""

        // Only refuse when the focus is clearly not a text target (a button, a list row,
        // a window with nothing focused inside). Everything else (web areas, editors,
        // terminals, custom views) gets the paste: a ⌘V that lands nowhere is harmless,
        // a transcript that silently stays on the clipboard is not.
        let nonEditableRoles: Set<String> = [
            kAXButtonRole as String, kAXCheckBoxRole as String, kAXRadioButtonRole as String,
            kAXPopUpButtonRole as String, kAXMenuButtonRole as String, kAXMenuItemRole as String,
            kAXSliderRole as String, kAXImageRole as String, kAXRowRole as String, kAXCellRole as String,
            kAXTableRole as String, kAXOutlineRole as String, kAXListRole as String,
            kAXWindowRole as String, kAXApplicationRole as String, kAXToolbarRole as String,
            kAXTabGroupRole as String, kAXDisclosureTriangleRole as String, kAXIncrementorRole as String,
        ]
        if nonEditableRoles.contains(role) {
            // A focused window or app with a text field inside still counts.
            if role == kAXWindowRole as String || role == kAXApplicationRole as String {
                var inner: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &inner) == .success,
                   let innerElement = inner {
                    var innerRoleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(innerElement as! AXUIElement, kAXRoleAttribute as CFString, &innerRoleRef)
                    let innerRole = (innerRoleRef as? String) ?? ""
                    return !nonEditableRoles.contains(innerRole)
                }
            }
            return false
        }
        return true
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
