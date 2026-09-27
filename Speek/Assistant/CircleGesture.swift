import AppKit

/// While the agent shortcut is held, circling something with the pointer sends the screen with
/// that circle drawn on it. No click needed: the pointer's recent path is drawn as a fading
/// stroke, and when it closes into a loop the loop is highlighted and the screen is captured.
/// Nothing from the screen is sent without a circle (or an explicit request to look).
@MainActor
final class CircleGesture {
    static let shared = CircleGesture()
    static let enabledKey = "speek.assistant.circleGesture"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Called with the annotated screenshot; a later circle replaces an earlier one.
    var onCircle: ((AssistantScreenContext) -> Void)?

    private var monitors: [Any] = []
    private var panel: NSPanel?
    private var view: CircleTrailView?
    private var screen: NSScreen?
    private var points: [(point: NSPoint, time: TimeInterval)] = []
    private var capturing = false
    private var fade: Task<Void, Never>?

    func start() {
        guard Self.isEnabled, monitors.isEmpty else { return }
        fade?.cancel()
        points = []; capturing = false
        let track: (NSEvent) -> Void = { [weak self] _ in self?.moved(NSEvent.mouseLocation) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: track) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { track($0); return $0 }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        points = []
        view?.trail = []
        view?.needsDisplay = true
        // A captured loop stays visible for a moment so the user sees what was sent.
        let hasLoop = view?.loop != nil
        fade = Task { [weak self] in
            if hasLoop { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.view?.loop = nil
        }
    }

    // MARK: Tracking

    private func moved(_ location: NSPoint) {
        guard !capturing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        points.append((location, now))
        points.removeAll { now - $0.time > 1.6 }
        show(on: NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main)
        guard let screen, let view else { return }
        view.trail = points.map { NSPoint(x: $0.point.x - screen.frame.minX, y: $0.point.y - screen.frame.minY) }
        view.needsDisplay = true
        if let loop = Self.loop(in: points.map(\.point), times: points.map(\.time)) { capture(loop) }
    }

    /// The most recent closed loop in the path: the pointer came back near where it was at least
    /// 0.3 s earlier, around an area at least 36 points each way. Straight back-and-forth
    /// movement is too thin to count.
    nonisolated static func loop(in path: [NSPoint], times: [TimeInterval]) -> [NSPoint]? {
        guard path.count >= 12, let last = path.last, let now = times.last else { return nil }
        for index in 0..<(path.count - 10) where now - times[index] >= 0.3 {
            let start = path[index]
            guard hypot(start.x - last.x, start.y - last.y) < 24 else { continue }
            let loop = Array(path[index...])
            let xs = loop.map(\.x), ys = loop.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                  maxX - minX >= 36, maxY - minY >= 36 else { continue }
            let length = zip(loop, loop.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            guard length >= 140 else { continue }
            return loop
        }
        return nil
    }

    private func capture(_ loop: [NSPoint]) {
        guard let screen else { return }
        capturing = true
        points = []
        view?.trail = []
        view?.loop = loop.map { NSPoint(x: $0.x - screen.frame.minX, y: $0.y - screen.frame.minY) }
        view?.needsDisplay = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        Task { [weak self] in
            defer { self?.capturing = false }
            guard let context = try? await ScreenContext.shared.captureCircled(loop, on: screen) else { return }
            NSSound(named: "Tink")?.play()
            self?.onCircle?(context)
        }
    }

    // MARK: Overlay

    private func show(on target: NSScreen?) {
        guard let target else { return }
        if panel == nil || screen != target {
            panel?.orderOut(nil)
            let window = NSPanel(contentRect: target.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let trail = CircleTrailView(frame: NSRect(origin: .zero, size: target.frame.size))
            trail.loop = view?.loop
            window.contentView = trail
            panel = window; view = trail; screen = target
        }
        if panel?.isVisible == false { panel?.orderFrontRegardless() }
    }
}

/// Draws the pointer's recent path, fading toward its oldest point, and a captured loop.
private final class CircleTrailView: NSView {
    var trail: [NSPoint] = []
    var loop: [NSPoint]?

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        if let loop, loop.count > 2 {
            let path = NSBezierPath()
            path.move(to: loop[0])
            loop.dropFirst().forEach { path.line(to: $0) }
            path.close()
            accent.withAlphaComponent(0.14).setFill(); path.fill()
            path.lineWidth = 3; path.lineJoinStyle = .round; path.lineCapStyle = .round
            accent.setStroke(); path.stroke()
        }
        guard trail.count > 1 else { return }
        for index in 1..<trail.count {
            let segment = NSBezierPath()
            segment.move(to: trail[index - 1]); segment.line(to: trail[index])
            segment.lineWidth = 3; segment.lineCapStyle = .round
            accent.withAlphaComponent(0.15 + 0.75 * CGFloat(index) / CGFloat(trail.count)).setStroke()
            segment.stroke()
        }
    }
}
