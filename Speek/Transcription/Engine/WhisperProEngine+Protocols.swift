import Foundation

// MARK: - RecorderStateProvider

extension SpeekEngine: RecorderStateProvider {
    /// The Copy button in the recorder: puts the unpasted transcript on the clipboard.
    func copyPasteHintText() {
        guard let text = pasteHintCopyText else { return }
        _ = ClipboardManager.setClipboard(text, transient: false, sessionID: nil)
        recorderUIManager?.confirmPasteHintCopied()
    }
}
