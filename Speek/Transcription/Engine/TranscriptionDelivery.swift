import Foundation
import os

@MainActor
final class TranscriptionDelivery {
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "TranscriptionDelivery")

    struct Request {
        let transcription: Transcription
        let text: String?
        let output: OutputRuntimeConfiguration
        let responseConfig: EnhancementRuntimeConfiguration?
        let responseError: String?
        let isAssistantFollowUp: Bool
    }

    struct Actions {
        let setState: (RecordingState) -> Void
        let dismiss: () async -> Void
        // Called instead of `dismiss` when the transcript went to the clipboard
        // because no editable field was focused — shows a brief in-panel hint
        // before dismissing rather than a toast that overlaps the panel.
        let showPasteHint: (String) async -> Void
        let sendFollowUp: (String, Transcription) async -> Void
        let showResponse: (String, String?) async -> Void
        let failResponse: (String) async -> Void
    }

    func deliver(_ request: Request, actions: Actions) async {
        guard request.transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue else {
            await actions.dismiss()
            return
        }

        if request.isAssistantFollowUp {
            await deliverFollowUp(request, actions: actions)
            return
        }

        if request.output.outputMode == .respond,
           request.responseConfig != nil || request.responseError != nil {
            await deliverResponse(request, actions: actions)
            return
        }

        if request.output.outputMode == .customCommand {
            await deliverCustomCommand(request, actions: actions)
            return
        }

        if let text = request.text {
            await paste(text, output: request.output, actions: actions)
        } else {
            await actions.dismiss()
        }
    }

    private func deliverFollowUp(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        actions.setState(.enhancing)
        await actions.sendFollowUp(text, item.transcription)
    }

    private func deliverResponse(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        if let responseError = item.responseError {
            await actions.failResponse("Enhancement failed: \(responseError)")
        } else if let text = item.text,
                  item.responseConfig != nil {
            await actions.showResponse(text, item.transcription.aiRequestSystemMessage)
        } else {
            await actions.failResponse("No response was generated.")
        }
    }

    private func deliverCustomCommand(_ item: Request, actions: Actions) async {
        guard let text = item.text else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.noTextToDeliver)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        guard let customCommand = item.output.customCommand,
              let command = customCommand.trimmedCommand else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.commandNotConfigured)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        let commandText = deliverableText(from: text)
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        Task {
            await runCustomCommand(command: command, commandText: commandText)
        }
    }

    private func runCustomCommand(command: String, commandText: String) async {
        let startTime = Date()
        logger.notice("Custom command started")

        do {
            let result = try await CustomCommandDeliveryRunner.run(
                command: command,
                timeout: 10,
                context: CustomCommandDeliveryContext(transcript: commandText)
            )

            let duration = Date().timeIntervalSince(startTime)
            let stdoutBytes = result.stdout.utf8.count
            let stderrBytes = result.stderr.utf8.count

            if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.notice("Custom command stdout bytes=\(stdoutBytes, privacy: .public): \(result.stdout, privacy: .public)")
            }

            if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.notice(
                    "Custom command succeeded with stderr duration=\(Self.formattedDuration(duration), privacy: .public)s stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public): \(result.stderr, privacy: .public)"
                )
            } else {
                logger.notice(
                    "Custom command succeeded duration=\(Self.formattedDuration(duration), privacy: .public)s stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public)"
                )
            }
        } catch {
            notifyCustomCommandFailure(error, duration: Date().timeIntervalSince(startTime))
        }
    }

    private func notifyCustomCommandFailure(_ error: Error, duration: TimeInterval? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let duration {
            logger.error("Custom command failed duration=\(Self.formattedDuration(duration), privacy: .public)s: \(message, privacy: .public)")
        } else {
            logger.error("Custom command failed: \(message, privacy: .public)")
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

    private func paste(_ text: String, output: OutputRuntimeConfiguration, actions: Actions) async {
        let textToPaste = deliverableText(from: text)
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let pastedText = textToPaste + (appendSpace ? " " : "")
        SoundManager.shared.playStopSound()

        // An agent panel is up (Claude Code / Codex): the dictation goes into its reply
        // box, and Return there sends it to the agent's terminal.
        let agentPanelIsUp = await MainActor.run { AgentUpdateCenter.shared.isShowingPanel }
        if agentPanelIsUp {
            await actions.dismiss()
            await MainActor.run { AgentUpdateCenter.shared.insertTranscript(textToPaste) }
            return
        }

        // "Paste result text" off: copy only, show the hint, never press keys.
        let pasteEnabled = UserDefaults.standard.object(forKey: "speek.pasteResultText") as? Bool ?? true
        if !pasteEnabled {
            _ = ClipboardManager.setClipboard(pastedText, transient: true, sessionID: nil)
            await actions.showPasteHint(pastedText)
            return
        }

        // Check editability up front (not just inside CursorPaster) so we know
        // whether to dismiss now or leave the panel up to show the paste hint.
        guard CursorPaster.focusedElementLikelyEditable() else {
            // transient: true tags the dictated text as auto-generated/transient
            // (org.nspasteboard) so clipboard managers like Maccy/Raycast don't
            // permanently store it — it stays pasteable via ⌘V either way.
            _ = ClipboardManager.setClipboard(pastedText, transient: true, sessionID: nil)
            await actions.showPasteHint(pastedText)
            return
        }

        await actions.dismiss()

        let pasteTask = CursorPaster.startPasteAtCursor(pastedText)

        let autoSendKey = output.outputMode == .paste ? output.autoSendKey : .none
        Task { @MainActor in
            let pasteResult = await pasteTask.value

            // Only press Enter if we actually pasted into a field; if the text was
            // diverted to the clipboard (no editable target) there's nothing to send.
            if autoSendKey.isEnabled, pasteResult.didPostPasteCommand {
                // Give the target app a moment to register the pasted text before Enter,
                // but keep it short so "speak → Enter → sent" feels immediate.
                try? await Task.sleep(nanoseconds: 250_000_000)
                CursorPaster.performAutoSend(autoSendKey)
            }
        }
    }

    private func deliverableText(from text: String) -> String {
        normalizeSlashCommands(in: text)
    }

    /// Final-stage cleanup for slash commands, applied right before the text is
    /// pasted — so it runs AFTER any AI enhancement, which otherwise re-adds the
    /// trailing period that stops "/figma:figma-use" being recognised as a command.
    private func normalizeSlashCommands(in text: String) -> String {
        var result = text

        // Collapse "/ word" → "/word" (e.g. "/ compact" → "/compact").
        if let slashRegex = try? NSRegularExpression(pattern: "/\\s+(?=\\S)") {
            let range = NSRange(result.startIndex..., in: result)
            result = slashRegex.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: "/"
            )
        }

        // Turn a period right after a slash command into a space, so the trailing
        // space confirms the command and the skill menu appears.
        if let dotRegex = try? NSRegularExpression(pattern: "(/[\\p{L}\\p{N}:_-]+)\\.") {
            let range = NSRange(result.startIndex..., in: result)
            result = dotRegex.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: "$1 "
            )
        }

        return result
    }
}
