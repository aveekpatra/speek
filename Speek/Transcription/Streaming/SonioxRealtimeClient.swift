import Foundation
import LLMkit

/// In-app copy of LLMkit's Soniox real-time client so the connect config can be
/// tuned without forking the package. The one behavioral difference: with language
/// "auto" it sends `language_hints` restricted to the user's preferred languages
/// (Settings > Languages) — without hints Soniox occasionally misdetected Czech
/// speech as Polish, Russian, or Slovak.
final class SonioxRealtimeClient: @unchecked Sendable {

    /// Languages the user dictates in; sent as strict hints in "auto" mode.
    /// Read fresh at connect time from Settings > Languages (falls back to cs+en).
    private static var autoLanguageHints: [String] {
        UserDefaults.standard.preferredLanguageHints
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<LLMkit.StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var finalText = ""

    private(set) var transcriptionEvents: AsyncStream<LLMkit.StreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<LLMkit.StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        eventsContinuation?.finish()
    }

    func connect(apiKey: String, model: String, language: String?, customVocabulary: [String] = []) async throws {
        let urlString = "wss://stt-rt.soniox.com/transcribe-websocket"
        guard let url = URL(string: urlString) else {
            throw LLMKitError.invalidURL(urlString)
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        self.urlSession = session
        self.webSocketTask = task
        task.resume()

        // Send initial configuration (API key is in the config JSON, not HTTP header)
        try await sendConfiguration(apiKey: apiKey, model: model, language: language, customVocabulary: customVocabulary)

        eventsContinuation?.yield(.sessionStarted)

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw LLMKitError.networkError("Not connected to Soniox streaming.")
        }
        // Soniox expects raw binary audio frames
        try await task.send(.data(data))
    }

    func commit() async throws {
        guard let task = webSocketTask else {
            throw LLMKitError.networkError("Not connected to Soniox streaming.")
        }

        let finalizeMessage: [String: Any] = ["type": "finalize"]
        let jsonData = try JSONSerialization.data(withJSONObject: finalizeMessage)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        try await task.send(.string(jsonString))
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        eventsContinuation?.finish()
        finalText = ""
    }

    // MARK: - Private

    private func sendConfiguration(apiKey: String, model: String, language: String?, customVocabulary: [String]) async throws {
        guard let task = webSocketTask else {
            throw LLMKitError.networkError("Not connected to Soniox streaming.")
        }

        let config = Self.makeConfigPayload(
            apiKey: apiKey,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            preferredHints: Self.autoLanguageHints
        )

        let jsonData = try JSONSerialization.data(withJSONObject: config)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        try await task.send(.string(jsonString))
    }

    /// Builds the Soniox connect config. Pure and internal so the hint + context.general
    /// logic can be unit-tested without a live socket. Alongside the strict language hints
    /// it always sends `context.general` — the documented rescue for wrong-language output
    /// (https://soniox.com/docs/stt/concepts/context) — which was the last thing letting
    /// Czech surface as English.
    static func makeConfigPayload(
        apiKey: String,
        model: String,
        language: String?,
        customVocabulary: [String],
        preferredHints: [String]
    ) -> [String: Any] {
        var config: [String: Any] = [
            "api_key": apiKey,
            "model": model,
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1
        ]

        let hints: [String]
        let general: [[String: String]]

        if let language, language != "auto", !language.isEmpty {
            // A concrete language is pinned: hint only that language and tell Soniox to
            // output nothing else (the docs' recommended single-language pattern).
            hints = [language]
            let name = LanguageDictionary.all[language] ?? language
            general = [
                ["key": "language", "value": name],
                ["key": "instructions", "value": "Output the transcription only in \(name)."]
            ]
        } else {
            // Auto mode: restrict detection to the user's chosen languages and treat the
            // first as primary, so short ambiguous words resolve to it instead of a
            // lookalike language (Polish/Russian/Slovak).
            hints = preferredHints
            let primaryCode = preferredHints.first ?? "en"
            let primary = LanguageDictionary.all[primaryCode] ?? primaryCode
            let others = preferredHints.dropFirst().map { LanguageDictionary.all[$0] ?? $0 }
            let instructions: String
            if others.isEmpty {
                instructions = "The speaker primarily speaks \(primary). When the language is ambiguous, prefer \(primary)."
            } else {
                instructions = "The speaker primarily speaks \(primary). They may occasionally switch to \(others.joined(separator: ", ")). When the language is ambiguous, prefer \(primary)."
            }
            general = [
                ["key": "language", "value": primary],
                ["key": "instructions", "value": instructions]
            ]
        }

        config["language_hints"] = hints
        config["language_hints_strict"] = true

        // general and terms are sibling sections of context (max 8000 tokens combined).
        var context: [String: Any] = ["general": general]
        if !customVocabulary.isEmpty {
            context["terms"] = customVocabulary
        }
        config["context"] = context

        return config
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    eventsContinuation?.yield(.error(error.localizedDescription))
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Check for error
        if let errorCode = json["error_code"] as? Int {
            let errorMsg = json["error_message"] as? String ?? "Unknown error (code \(errorCode))"
            eventsContinuation?.yield(.error(errorMsg))
            return
        }

        // Check for finished signal
        if let finished = json["finished"] as? Bool, finished {
            if !finalText.isEmpty {
                eventsContinuation?.yield(.committed(text: finalText))
                finalText = ""
            } else {
                eventsContinuation?.yield(.committed(text: ""))
            }
            return
        }

        // Parse tokens
        guard let tokens = json["tokens"] as? [[String: Any]], !tokens.isEmpty else { return }
        processTokens(tokens)
    }

    private func processTokens(_ tokens: [[String: Any]]) {
        var newFinalText = ""
        var newPartialText = ""
        var sawFinMarker = false

        for token in tokens {
            guard let text = token["text"] as? String else { continue }

            if text == "<fin>" {
                sawFinMarker = true
                continue
            }

            let isFinal = token["is_final"] as? Bool ?? false

            if isFinal {
                newFinalText += text
            } else {
                newPartialText += text
            }
        }

        if !newFinalText.isEmpty {
            finalText += newFinalText
        }

        if sawFinMarker {
            eventsContinuation?.yield(.committed(text: finalText))
            finalText = ""
        } else if !newPartialText.isEmpty || !newFinalText.isEmpty {
            // Emit a partial whenever the running transcript changed, even if only
            // `is_final=true` tokens arrived in this batch — otherwise the live
            // preview lags behind.
            let currentPartial = finalText + newPartialText
            eventsContinuation?.yield(.partial(text: currentPartial))
        }
    }
}
