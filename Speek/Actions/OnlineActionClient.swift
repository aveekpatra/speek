import Foundation

enum ActionClientError: LocalizedError {
    case missingKey
    case invalidResponse
    case requestFailed(String)
    case recordingTooLarge

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add an OpenRouter or OpenAI API key to use online voice and requests."
        case .invalidResponse: return "The model returned a response Speek could not read."
        case .requestFailed(let message): return message
        case .recordingTooLarge: return "This recording is too large to send. Keep it under 24 MB."
        }
    }
}

enum ProposedActionKind: String, Codable, Hashable {
    case openWebsite = "open_website"
    case searchWeb = "search_web"
    case openApp = "open_app"
    case remember
    case toolCall = "tool_call"
    case answer
    case unsupported
}

struct ProposedAction: Codable {
    let kind: ProposedActionKind
    let title: String
    let target: String
    let response: String

    var requiresReview: Bool { kind == .toolCall }
}

final class OnlineActionClient {
    static let shared = OnlineActionClient()
    private init() {}

    private var apiKey: String? {
        ActionCredentials.key(for: .openAI)
    }

    func transcribe(_ audioURL: URL, language forced: String? = nil) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw ActionClientError.missingKey }
        let audio = try Data(contentsOf: audioURL)
        guard audio.count < 24_000_000 else { throw ActionClientError.recordingTooLarge }
        let boundary = "Speek-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let allowedSpeechModels = ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
        let requestedSpeechModel = UserDefaults.standard.string(forKey: "speek.actions.speechModel") ?? "gpt-transcribe"
        let speechModel = allowedSpeechModels.contains(requestedSpeechModel) ? requestedSpeechModel : "gpt-transcribe"
        field("model", speechModel)
        for (name, value) in VoiceCapturePreferences.openAIFields(model: speechModel, forcing: forced) { field(name, value) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 90
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else { throw ActionClientError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func propose(_ requestText: String, history: [ActionMessage], contextNotes: String?) async throws -> ProposedAction {
        guard let apiKey, !apiKey.isEmpty else { throw ActionClientError.missingKey }
        let recent = history.suffix(8).map { "\($0.role.rawValue): \(String($0.text.prefix(700)))" }.joined(separator: "\n")
        let instructions = """
        You route requests for a macOS voice assistant. Available actions are open_website, search_web, answer, unsupported.
        Use open_website for opening a named public website. Put a full https URL in target. Never use file, javascript, data, localhost, or internal URLs.
        Use search_web for a web search. Put the search terms in target.
        Use answer for conversation. Put a concise answer in response. Do not claim you performed an action.
        Use tool_call for tools listed in context. Target is a serialized tool/arguments object. Use unsupported only when the needed integration is not available.
        Title is a short, plain description. Empty strings are allowed for unused target or response.
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": ["open_website", "search_web", "open_app", "remember", "tool_call", "answer", "unsupported"]],
                "title": ["type": "string"],
                "target": ["type": "string"],
                "response": ["type": "string"]
            ],
            "required": ["kind", "title", "target", "response"],
            "additionalProperties": false
        ]
        let routingModel = UserDefaults.standard.string(forKey: "speek.actions.routingModel") == "gpt-4o"
            ? "gpt-4o" : "gpt-4o-mini"
        let payload: [String: Any] = [
            "model": routingModel,
            "instructions": instructions,
            "input": "User-provided task context:\n\(contextNotes ?? "None")\n\nRecent thread:\n\(recent)\n\nCurrent request:\n\(requestText)",
            "store": false,
            "text": ["format": ["type": "json_schema", "name": "speek_action", "strict": true, "schema": schema]]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = object["output"] as? [[String: Any]] else { throw ActionClientError.invalidResponse }
        let texts = output.flatMap { ($0["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String } }
        guard let result = texts.first?.data(using: .utf8),
              let action = try? JSONDecoder().decode(ProposedAction.self, from: result) else {
            throw ActionClientError.invalidResponse
        }
        return action
    }

    func speak(_ text: String) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty else { throw ActionClientError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts", "voice": "nova", "input": String(text.prefix(4_000)), "response_format": "mp3"
        ])
        request.timeoutInterval = 90
        let data = try await send(request)
        guard !data.isEmpty else { throw ActionClientError.invalidResponse }
        return data
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ActionClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "OpenAI request failed (HTTP \(response.statusCode))."
            throw ActionClientError.requestFailed(message)
        }
        return data
    }
}
