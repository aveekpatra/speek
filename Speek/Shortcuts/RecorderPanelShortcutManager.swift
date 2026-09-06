import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class RecorderPanelShortcutManager: ObservableObject {
    private var recorderUIManager: RecorderUIManager
    private var visibilityTask: Task<Void, Never>?
    private var shortcutChangeObserver: NSObjectProtocol?
    private let visibleRecorderMonitor = ShortcutMonitor()
    private var fallbackHotKeys: RecorderPanelHotKeyFallback?
    private var modifierFallback: RecorderPanelModifierFallback?
    
    // Double-tap Escape handling
    private var firstEscapePressTime: Date? = nil
    private let escapeDoublePressThreshold: TimeInterval = 1.5
    private var escapeTimeoutTask: Task<Void, Never>?
    
    init(recorderUIManager: RecorderUIManager) {
        self.recorderUIManager = recorderUIManager
        setupShortcutChangeObserver()
        setupVisibilityObserver()
    }

    private func setupShortcutChangeObserver() {
        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let action = notification.object as? ShortcutAction else {
                return
            }

            guard action == .cancelRecorder ||
                    action == .primaryRecording ||
                    action == .secondaryRecording else {
                return
            }

            Task { @MainActor in
                self?.refreshVisibleShortcuts()
            }
        }
    }

    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in recorderUIManager.$isRecorderPanelVisible.values {
                if isVisible {
                    refreshVisibleShortcuts()
                } else {
                    visibleRecorderMonitor.stop()
                    stopFallbackHotKeys()
                    stopModifierFallback()
                    resetEscapeState()
                }
            }
        }
    }

    private var canUseModeShortcuts: Bool {
        !ModeManager.shared.enabledConfigurations.isEmpty
    }

    private func resetEscapeState() {
        firstEscapePressTime = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
        recorderUIManager.setCancelConfirming(false)
    }
    
    private func refreshVisibleShortcuts() {
        guard recorderUIManager.isRecorderPanelVisible else {
            visibleRecorderMonitor.stop()
            stopFallbackHotKeys()
            stopModifierFallback()
            resetEscapeState()
            return
        }

        startFallbackHotKeys()

        if !AXIsProcessTrusted() {
            startModifierFallback()
        } else {
            stopModifierFallback()
        }

        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.recorderPanelStoredActions)

        if canUseModeShortcuts {
            for (index, keyCode) in Self.digitKeyCodes.enumerated() {
                shortcuts[.recorderPanelMode(index)] = .key(
                    keyCode: keyCode,
                    modifierFlags: [.option]
                )
            }
        }

        visibleRecorderMonitor.start(
            shortcuts: shortcuts,
            onKeyDown: { [weak self] action, _ in
                Task { @MainActor in
                    await self?.handleRecorderPanelShortcut(action)
                }
            },
            onKeyUp: { _, _ in }
        )
    }

    private func handleRecorderPanelShortcut(_ action: ShortcutAction) async {
        guard recorderUIManager.isRecorderPanelVisible else { return }

        switch action {
        case .cancelRecorder:
            guard ShortcutStore.shortcut(for: .cancelRecorder) != nil else { return }
            await recorderUIManager.cancelRecording()
        case .recorderPanelEscape:
            await handleEscapeShortcut()
        case .recorderPanelCommit:
            guard recorderUIManager.currentRecordingState == .recording else { return }
            await recorderUIManager.commitWithAutoSend()
        case .recorderPanelMode(let index):
            handleModeSelectionShortcut(index: index)
        default:
            break
        }
    }

    private func startFallbackHotKeys() {
        if fallbackHotKeys == nil {
            fallbackHotKeys = RecorderPanelHotKeyFallback { [weak self] action in
                Task { @MainActor in
                    await self?.handleRecorderPanelShortcut(action)
                }
            }
        }
        fallbackHotKeys?.start()
    }

    private func stopFallbackHotKeys() {
        fallbackHotKeys?.stop()
        fallbackHotKeys = nil
    }

    private func startModifierFallback() {
        if modifierFallback == nil {
            modifierFallback = RecorderPanelModifierFallback { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.recorderUIManager.isRecorderPanelVisible else {
                        return
                    }
                    await self.recorderUIManager.toggleRecorderPanel()
                }
            }
        }

        modifierFallback?.updateShortcuts(activeModifierRecordingShortcuts())
        modifierFallback?.start()
    }

    private func stopModifierFallback() {
        modifierFallback?.stop()
        modifierFallback = nil
    }

    private func activeModifierRecordingShortcuts() -> [Shortcut] {
        var shortcuts: [Shortcut] = []

        if isRecordingShortcutEnabled(.primaryRecording),
           let shortcut = ShortcutStore.shortcut(for: .primaryRecording),
           shortcut.isModifierOnly {
            shortcuts.append(shortcut)
        }

        if isRecordingShortcutEnabled(.secondaryRecording),
           let shortcut = ShortcutStore.shortcut(for: .secondaryRecording),
           shortcut.isModifierOnly {
            shortcuts.append(shortcut)
        }

        return shortcuts
    }

    private func isRecordingShortcutEnabled(_ action: ShortcutAction) -> Bool {
        switch action {
        case .primaryRecording:
            return UserDefaults.standard.string(forKey: "primaryRecordingShortcut") != "none"
        case .secondaryRecording:
            return UserDefaults.standard.string(forKey: "secondaryRecordingShortcut") == "custom"
        default:
            return false
        }
    }

    private func handleEscapeShortcut() async {
        guard ShortcutStore.shortcut(for: .cancelRecorder) == nil else { return }

        let now = Date()
        if let firstTime = firstEscapePressTime,
           now.timeIntervalSince(firstTime) <= escapeDoublePressThreshold {
            resetEscapeState()
            await recorderUIManager.cancelRecordingAnimated()
            return
        }

        firstEscapePressTime = now
        // Show the in-panel confirm overlay (blurred transcript + "Esc again to cancel")
        // instead of a toast.
        recorderUIManager.setCancelConfirming(true)
        escapeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.escapeDoublePressThreshold ?? 1.5) * 1_000_000_000))
            await MainActor.run {
                self?.firstEscapePressTime = nil
                self?.recorderUIManager.setCancelConfirming(false)
            }
        }
    }

    private func handleModeSelectionShortcut(index: Int) {
        guard canUseModeShortcuts else { return }

        let modeManager = ModeManager.shared
        let availableConfigurations = modeManager.enabledConfigurations

        guard index < availableConfigurations.count else { return }

        let selectedConfig = availableConfigurations[index]
        modeManager.setActiveConfiguration(selectedConfig)
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }

        visibilityTask?.cancel()
        MainActor.assumeIsolated {
            visibleRecorderMonitor.stop()
            stopFallbackHotKeys()
            stopModifierFallback()
            resetEscapeState()
        }
    }

    private static let digitKeyCodes: [UInt16] = [
        UInt16(kVK_ANSI_1),
        UInt16(kVK_ANSI_2),
        UInt16(kVK_ANSI_3),
        UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5),
        UInt16(kVK_ANSI_6),
        UInt16(kVK_ANSI_7),
        UInt16(kVK_ANSI_8),
        UInt16(kVK_ANSI_9),
        UInt16(kVK_ANSI_0)
    ]
}

private final class RecorderPanelModifierFallback {
    private let handler: () -> Void
    private var shortcuts: [Shortcut] = []
    private var timer: DispatchSourceTimer?
    private var isDown = false
    private var lastTriggerAt = Date.distantPast
    private let triggerCooldown: TimeInterval = 0.25

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func updateShortcuts(_ shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
    }

    func start() {
        guard timer == nil else { return }
        guard !shortcuts.isEmpty else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isDown = false
    }

    private func tick() {
        guard !shortcuts.isEmpty else {
            stop()
            return
        }

        let flags = currentModifierFlags()
        let matched = shortcuts.contains { matches($0, flags: flags) }

        if matched && !isDown {
            let now = Date()
            if now.timeIntervalSince(lastTriggerAt) >= triggerCooldown {
                lastTriggerAt = now
                handler()
            }
        }

        isDown = matched
    }

    private func currentModifierFlags() -> NSEvent.ModifierFlags {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
    }

    private func matches(_ shortcut: Shortcut, flags: NSEvent.ModifierFlags) -> Bool {
        guard shortcut.isModifierOnly else { return false }
        let normalized = Shortcut.normalizedModifierFlags(flags, forKeyCode: nil)
        return normalized == shortcut.modifierFlags
    }
}

private final class RecorderPanelHotKeyFallback {
    private enum HotKeyID: UInt32 {
        case commit = 1
        case escape = 2
    }

    private let handler: (ShortcutAction) -> Void
    private var eventHandler: EventHandlerRef?
    private var commitHotKey: EventHotKeyRef?
    private var escapeHotKey: EventHotKeyRef?
    private var isStarted = false

    init(handler: @escaping (ShortcutAction) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event,
                  let userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let fallback = Unmanaged<RecorderPanelHotKeyFallback>
                .fromOpaque(userData)
                .takeUnretainedValue()
            fallback.handle(hotKeyID.id)
            return noErr
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandler
        ) == noErr else {
            return
        }

        guard registerHotKey(keyCode: UInt32(kVK_Return), id: .commit, ref: &commitHotKey),
              registerHotKey(keyCode: UInt32(kVK_Escape), id: .escape, ref: &escapeHotKey) else {
            stop()
            return
        }

        isStarted = true
    }

    func stop() {
        if let commitHotKey {
            UnregisterEventHotKey(commitHotKey)
            self.commitHotKey = nil
        }

        if let escapeHotKey {
            UnregisterEventHotKey(escapeHotKey)
            self.escapeHotKey = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        isStarted = false
    }

    private func registerHotKey(
        keyCode: UInt32,
        id: HotKeyID,
        ref: inout EventHotKeyRef?
    ) -> Bool {
        var hotKeyID = EventHotKeyID(
            signature: RecorderPanelHotKeyFallback.signature,
            id: id.rawValue
        )
        return RegisterEventHotKey(
            keyCode,
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        ) == noErr
    }

    private func handle(_ id: UInt32) {
        switch HotKeyID(rawValue: id) {
        case .commit:
            handler(.recorderPanelCommit)
        case .escape:
            handler(.recorderPanelEscape)
        case nil:
            break
        }
    }

    private static let signature: OSType = {
        "WPRP".utf8.reduce(OSType(0)) { result, byte in
            (result << 8) + OSType(byte)
        }
    }()
}
