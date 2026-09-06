import Foundation

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RecordingState { get }
    var partialTranscript: String { get }
    // Stable committed text vs the revising tail, for jump-free live rendering.
    var committedTranscript: String { get }
    var partialTail: String { get }
    // Escape-to-cancel overlay state.
    var isCancelConfirming: Bool { get }
    var isCanceling: Bool { get }
    // Set when the transcript couldn't be auto-pasted (no editable field focused);
    // the panel shows this text briefly instead of the toast notification.
    var pasteHintText: String? { get }
    /// Final transcript shown alongside the paste hint when it could not be pasted.
    var resultPreview: String? { get }
}
