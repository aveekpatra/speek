// Tracks release during asynchronous microphone startup as well as normal holds.
struct HoldToSpeak {
    private enum State { case idle, preparing, recording, releasedWhilePreparing }
    private var state: State = .idle
    var isEngaged: Bool { state != .idle }

    mutating func press() -> Bool {
        guard state == .idle else { return false }
        state = .preparing
        return true
    }

    // True means finish an already-running recording.
    mutating func release() -> Bool {
        switch state {
        case .preparing: state = .releasedWhilePreparing; return false
        case .recording: state = .idle; return true
        case .idle, .releasedWhilePreparing: return false
        }
    }

    // True means the key was released before the microphone became ready.
    mutating func didStartRecording() -> Bool {
        switch state {
        case .releasedWhilePreparing: state = .idle; return true
        case .preparing: state = .recording; return false
        case .idle, .recording: return false
        }
    }

    mutating func cancel() { state = .idle }
}
