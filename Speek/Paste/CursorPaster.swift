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

    /// What the accessibility tree says about the focused element before a paste.
    enum FocusProbe {
        /// A text field, text area, or an element inside an editable ancestor.
        case editable
        /// Positively not a text target: no focused window at all (empty desktop) or
        /// a control that never takes text (button, image, table row...).
        case notEditable
        /// The app exposes nothing usable: Electron apps before their tree is on,
        /// Gecko browsers that only report the window. Not evidence either way.
        case unknown
    }

    /// Roles that never accept pasted text.
    private static let nonTextRoles: Set<String> = [
        kAXButtonRole as String, kAXCheckBoxRole as String, kAXRadioButtonRole as String,
        kAXMenuItemRole as String, kAXMenuRole as String, kAXMenuBarItemRole as String,
        kAXImageRole as String, kAXStaticTextRole as String, "AXLink",
        kAXRowRole as String, kAXCellRole as String, kAXOutlineRole as String,
        kAXTableRole as String, kAXListRole as String, kAXSliderRole as String,
        kAXPopUpButtonRole as String, kAXTabGroupRole as String, kAXToolbarRole as String,
        kAXDisclosureTriangleRole as String, kAXIncrementorRole as String,
    ]

    /// Advisory: true when the focused element is confirmed as a text target. Never
    /// gates the paste itself; see `probeFocusedElement`.
    @MainActor
    static func focusedElementLikelyEditable() -> Bool {
        probeFocusedElement() == .editable
    }

    /// Advisory only: never gates the paste. Decides whether the previous clipboard is
    /// restored and, together with `verifyPasteLanded`, whether the recorder offers a
    /// Copy button. Gecko browsers report the window as focused until their tree is
    /// up and Electron apps report nothing, so `.unknown` is common and must never be
    /// read as "nowhere to paste".
    @MainActor
    static func probeFocusedElement() -> FocusProbe {
        guard AXIsProcessTrusted() else { return .editable } // can't detect -> behave as before

        // Electron / Chromium apps (ChatGPT, Slack, VS Code, Cursor...) keep their
        // accessibility tree off until a client asks for it; until then every read
        // fails with kAXErrorCannotComplete. Asking the frontmost app to turn it on
        // makes the focused element readable from the next call on.
        var frontApp: AXUIElement?
        if let front = NSWorkspace.shared.frontmostApplication {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            frontApp = app
        }

        guard let (element, role) = focusedElementAndRole(frontApp: frontApp) else {
            // Nothing readable in focus. An app with no focused window (the Finder on
            // an empty desktop) is positively nowhere to paste; anything else is an app
            // that has not told us, which is not the same thing.
            if let frontApp, !hasFocusedWindow(frontApp) {
                logger.notice("Frontmost app has no focused window; no paste target")
                return .notEditable
            }
            logger.notice("Focused element unknown; target unconfirmed")
            return .unknown
        }

        if isTextTarget(element, role: role) { return .editable }
        if nonTextRoles.contains(role) {
            logger.notice("Focused element role \(role, privacy: .public) never takes text")
            return .notEditable
        }
        logger.notice("Focused element role \(role, privacy: .public) not confirmed as a text target")
        return .unknown
    }

    /// Watches the frontmost app for the accessibility notifications a real paste
    /// produces: the focused control's value changed, or its selection moved. AppKit,
    /// Chromium/Electron and Gecko all post these when text lands, whatever role they
    /// gave the control. Create it before Cmd+V, read it afterwards.
    final class PasteWitness {
        private var observer: AXObserver?
        private(set) var sawTextChange = false
        /// What had focus when the witness was created, if the app said.
        private let focusedElement: AXUIElement?

        @MainActor
        init() {
            guard AXIsProcessTrusted(), let front = NSWorkspace.shared.frontmostApplication else {
                focusedElement = nil
                return
            }
            let pid = front.processIdentifier
            let app = AXUIElementCreateApplication(pid)
            focusedElement = focusedElementAndRole(frontApp: app)?.0

            // Browsers post value-changed for sliders, clocks and the URL bar while a
            // page runs, so only a change on the focused control or on a text target
            // counts as text landing.
            let callback: AXObserverCallback = { _, element, _, refcon in
                guard let refcon else { return }
                let witness = Unmanaged<PasteWitness>.fromOpaque(refcon).takeUnretainedValue()
                if let focused = witness.focusedElement, CFEqual(focused, element) {
                    witness.sawTextChange = true
                    return
                }
                if isTextTarget(element, role: axRole(of: element)) {
                    witness.sawTextChange = true
                }
            }
            var created: AXObserver?
            guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
                AXObserverAddNotification(observer, app, name as CFString, refcon)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.observer = observer
        }

        func stop() {
            guard let observer else { return }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.observer = nil
        }
    }

    /// After Cmd+V: did the text land? True when the witness saw the focused app's
    /// text change, or when the focused element's value now contains the text. Polls
    /// for up to ~0.8 s because the target app needs a moment to process the key
    /// event. False means the pill with its Copy button is warranted.
    @MainActor
    static func verifyPasteLanded(_ text: String, witness: PasteWitness) async -> Bool {
        guard AXIsProcessTrusted() else { return true }
        let needle = pasteNeedle(text)
        var frontApp: AXUIElement?
        if let front = NSWorkspace.shared.frontmostApplication {
            frontApp = AXUIElementCreateApplication(front.processIdentifier)
        }

        for _ in 0..<8 {
            await wait(0.1)
            if witness.sawTextChange {
                logger.notice("Paste verified: focused app reported a text change")
                return true
            }
            guard !needle.isEmpty, let (element, role) = focusedElementAndRole(frontApp: frontApp) else { continue }
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String, normalizedForMatch(value).contains(needle) {
                logger.notice("Paste verified: \(role, privacy: .public) value holds the text")
                return true
            }
        }
        logger.notice("Paste not verified: no text change seen and no value holds the text")
        return false
    }

    /// Focused element, looking one level into a window or application "focus".
    @MainActor
    private static func focusedElementAndRole(frontApp: AXUIElement?) -> (AXUIElement, String)? {
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
        guard status == .success, let focused = focusedRef else { return nil }
        var element = focused as! AXUIElement
        var role = axRole(of: element)

        // The window or application as "focus" means the app has not told us what is
        // inside. Look one level in; if nothing is there the target is unconfirmed.
        if role == kAXWindowRole as String || role == kAXApplicationRole as String {
            var inner: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &inner) == .success,
                  let innerElement = inner else {
                return nil
            }
            element = innerElement as! AXUIElement
            role = axRole(of: element)
        }
        return (element, role)
    }

    private static func hasFocusedWindow(_ app: AXUIElement) -> Bool {
        var windowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef)
        return status == .success && windowRef != nil
    }

    /// The start of the pasted text, whitespace-collapsed, so a long transcript still
    /// matches a value the app truncates or reflows.
    private static func pasteNeedle(_ text: String) -> String {
        String(normalizedForMatch(text).prefix(80))
    }

    private static func normalizedForMatch(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func axRole(of element: AXUIElement) -> String {
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
