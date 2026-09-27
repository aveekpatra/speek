import AppKit
import os

/// A mouse button that works like the speak shortcut: hold to talk, release to finish
/// (double-tap for hands-free follows the same setting). The chosen button is consumed so
/// it does not also open links or paste in the app under the pointer.
final class MouseTriggerMonitor {
    enum Button: Int, CaseIterable, Identifiable {
        case off = 0, middle = 2, back = 3, forward = 4
        var id: Int { rawValue }
        var title: String {
            switch self { case .off: return "Off"; case .middle: return "Middle button"; case .back: return "Back button"; case .forward: return "Forward button" }
        }
    }

    static let defaultsKey = "speek.dictation.mouseButton"
    static var selected: Button { Button(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .off }

    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buttonNumber: Int64 = 0
    private var onPress: ((TimeInterval) -> Void)?
    private var onRelease: ((TimeInterval) -> Void)?
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "MouseTrigger")

    func start(button: Button, onPress: @escaping (TimeInterval) -> Void, onRelease: @escaping (TimeInterval) -> Void) {
        stop()
        guard button != .off else { return }
        buttonNumber = Int64(button.rawValue)
        self.onPress = onPress
        self.onRelease = onRelease
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<MouseTriggerMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.mouseEventButtonNumber) == monitor.buttonNumber else { return Unmanaged.passUnretained(event) }
            let time = ProcessInfo.processInfo.systemUptime
            if type == .otherMouseDown { monitor.onPress?(time) } else if type == .otherMouseUp { monitor.onRelease?(time) }
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Could not install the mouse trigger event tap. Accessibility permission may be missing.")
            return
        }
        eventTap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; source = nil; onPress = nil; onRelease = nil
    }

    deinit { stop() }
}
