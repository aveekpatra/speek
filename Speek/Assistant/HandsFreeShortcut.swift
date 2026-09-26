import Foundation

/// Pure event state machine. Times must use one monotonic clock (systemUptime).
/// A quick first tap briefly defers finish; the second tap keeps the same recording running.
struct HandsFreeShortcut {
    enum Action: Equatable { case none, startRecording, finishRecording, waitForSecondTap }
    static let tapDuration: TimeInterval = 0.22
    static let secondTapWindow: TimeInterval = 0.32

    private(set) var isEngaged = false
    private(set) var isHandsFree = false
    private(set) var tapDeadline: TimeInterval?
    private var keyIsDown = false
    private var pressedAt: TimeInterval = 0
    private var microphoneReady = false
    private var finishWhenReady = false
    private var doubleTapEnabled = false

    mutating func press(at time: TimeInterval, enabled: Bool) -> Action {
        guard !keyIsDown else { return .none }
        if !isEngaged {
            isEngaged = true; keyIsDown = true; pressedAt = time
            doubleTapEnabled = enabled; microphoneReady = false; finishWhenReady = false
            return .startRecording
        }
        guard !finishWhenReady else { return .none }
        if let deadline = tapDeadline {
            tapDeadline = nil
            if time <= deadline {
                keyIsDown = true; isHandsFree = true
                return .none
            }
            return finish()
        }
        if isHandsFree { return finish() }
        return .none
    }

    mutating func release(at time: TimeInterval) -> Action {
        guard isEngaged, keyIsDown else { return .none }
        keyIsDown = false
        guard !isHandsFree else { return .none }
        if doubleTapEnabled && time >= pressedAt && time - pressedAt <= Self.tapDuration {
            tapDeadline = time + Self.secondTapWindow
            return .waitForSecondTap
        }
        return finish()
    }

    mutating func expireTapWindow(at time: TimeInterval) -> Action {
        guard let deadline = tapDeadline, time >= deadline, !keyIsDown, !isHandsFree else { return .none }
        tapDeadline = nil
        return finish()
    }

    mutating func didStartRecording() -> Action {
        guard isEngaged else { return .none }
        microphoneReady = true
        if finishWhenReady { cancel(); return .finishRecording }
        return .none
    }

    mutating func cancel() {
        isEngaged = false; isHandsFree = false; tapDeadline = nil; keyIsDown = false
        microphoneReady = false; finishWhenReady = false; doubleTapEnabled = false
    }

    private mutating func finish() -> Action {
        tapDeadline = nil; isHandsFree = false; keyIsDown = false
        if microphoneReady { cancel(); return .finishRecording }
        finishWhenReady = true
        return .none
    }
}
