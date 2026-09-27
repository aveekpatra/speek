import AppKit
import ApplicationServices
import Combine

enum VoiceInputMode: String, CaseIterable {
    case automatic = "Automatic", dictation = "Dictation", agent = "Agent"
}

struct VoiceTarget {
    let pid: pid_t
    let element: AXUIElement
    /// A text view in Speek's own windows; dictation is inserted directly instead of pasted.
    weak var localTextView: NSTextView?

    func isStillFocused() -> Bool {
        if let localTextView { return NSApp.keyWindow?.firstResponder === localTextView }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        var value: CFTypeRef?
        let root = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return false }
        return CFEqual(element, value)
    }
}

@MainActor
final class VoiceFocus: ObservableObject {
    static let shared = VoiceFocus()
    @Published private(set) var appName = "Speek"
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var detectedMode: VoiceInputMode = .agent
    @Published private(set) var permissionMissing = false
    @Published private(set) var secure = false
    @Published var override: VoiceInputMode = .automatic
    private(set) var target: VoiceTarget?
    /// The last text field in another app, for inserting an answer back where you were working.
    private(set) var lastExternalTarget: VoiceTarget?
    @Published private(set) var lastExternalAppName: String?
    private var timer: Timer?
    private var pid: pid_t = 0

    var mode: VoiceInputMode { override == .automatic ? detectedMode : override }
    var label: String { permissionMissing ? "Enable access" : secure ? "Private field" : mode.rawValue }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    static var defaultAppIcon: NSImage {
        if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            return NSWorkspace.shared.icon(forFile: finder.path)
        }
        return NSApplication.shared.applicationIconImage
    }

    private func clearTarget() {
        pid = 0
        appName = "Desktop"
        appIcon = Self.defaultAppIcon
        target = nil
        secure = false
        permissionMissing = !AXIsProcessTrusted()
        detectedMode = .agent
    }

    nonisolated static func isDesktop(bundleID: String?, hasFocusedWindow: Bool) -> Bool {
        bundleID == "com.apple.finder" && !hasFocusedWindow
    }

    func refresh() {
        guard let app = NSWorkspace.shared.frontmostApplication else { clearTarget(); return }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            refreshOwnWindow()
            return
        }
        let appRoot = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appRoot, 0.1)
        var focusedWindow: CFTypeRef?
        let hasFocusedWindow = AXUIElementCopyAttributeValue(appRoot, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success && focusedWindow != nil
        if Self.isDesktop(bundleID: app.bundleIdentifier, hasFocusedWindow: hasFocusedWindow) {
            clearTarget()
            appName = app.localizedName ?? "Finder"
            appIcon = app.icon ?? Self.defaultAppIcon
            return
        }
        let wasMissingPermission = permissionMissing
        if app.processIdentifier != pid || (wasMissingPermission && AXIsProcessTrusted()) {
            pid = app.processIdentifier
            appName = app.localizedName ?? "Current app"
            appIcon = app.icon
            // Chromium and Electron expose their focused editor after AX is enabled.
            if AXIsProcessTrusted() {
                let root = AXUIElementCreateApplication(pid)
                AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
        }
        permissionMissing = !AXIsProcessTrusted()
        target = nil
        secure = false
        detectedMode = .agent
        guard !permissionMissing else { return }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        secure = (subrole as? String) == "AXSecureTextField"
        guard !secure else { return }
        target = VoiceTarget(pid: pid, element: element)
        let role = CursorPaster.axRole(of: element)
        var enabled: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        guard (enabled as? Bool) != false else { return }
        var selectedTextSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedTextSettable)
        var rangeSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &rangeSettable)
        var editable: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editable)
        if Self.acceptsDictation(role: role, enabled: (enabled as? Bool) != false, secure: secure,
                                 editable: editable as? Bool, selectedTextWritable: selectedTextSettable.boolValue,
                                 selectionWritable: rangeSettable.boolValue) {
            detectedMode = .dictation
            lastExternalTarget = target
            if lastExternalAppName != appName { lastExternalAppName = appName }
        }
    }

    /// Speek's own text fields (composer, Create Prompt, editors) accept dictation too.
    /// The notch panel is excluded: speaking there is an agent request.
    private func refreshOwnWindow() {
        guard let window = NSApp.keyWindow, !(window is AssistantPanel),
              let textView = window.firstResponder as? NSTextView, textView.isEditable else { clearTarget(); return }
        pid = ProcessInfo.processInfo.processIdentifier
        appName = "Speek"
        appIcon = NSApplication.shared.applicationIconImage
        permissionMissing = !AXIsProcessTrusted()
        secure = (textView.delegate as? NSSecureTextField) != nil
        target = secure ? nil : VoiceTarget(pid: pid, element: AXUIElementCreateApplication(pid), localTextView: textView)
        detectedMode = secure ? .agent : .dictation
    }

    nonisolated static func acceptsDictation(role: String, enabled: Bool, secure: Bool, editable: Bool?,
                                             selectedTextWritable: Bool, selectionWritable: Bool) -> Bool {
        guard enabled, !secure, editable != false else { return false }
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
            || selectedTextWritable || selectionWritable || editable == true
    }
}
