import Foundation
import os

/// S1-mini by Superwhisper: turns raw transcripts into clean written text, locally.
/// Prompt contract from the model card: Qwen3 chat template with thinking disabled,
/// a fixed system prompt, and a control line above the transcript.
final class S1MiniService {
    static let shared = S1MiniService()

    enum Styling: String, CaseIterable, Identifiable {
        case casual, semiCasual = "semi-casual", semiFormal = "semi-formal", formal
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .casual: return "Casual"
            case .semiCasual: return "Semi-casual"
            case .semiFormal: return "Semi-formal"
            case .formal: return "Formal"
            }
        }
    }

    enum Structure: String, CaseIterable, Identifiable {
        case prose, lists
        var id: String { rawValue }
        var displayName: String { self == .prose ? "Prose" : "Lists" }
    }

    enum Context: String {
        case general, email
    }

    enum ServiceError: LocalizedError {
        case notDownloaded

        var errorDescription: String? {
            switch self {
            case .notDownloaded: return String(localized: "S1-mini is not downloaded yet. Download it in Models library.")
            }
        }
    }

    static let systemPrompt = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."

    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "S1MiniService")
    private let queue = DispatchQueue(label: "com.aveekpatra.speek.s1mini", qos: .userInitiated)
    private var runner: LlamaRunner?

    private init() {}

    func normalize(_ transcript: String, styling: Styling, structure: Structure, context: Context) async throws -> String {
        let path = S1MiniModelManager.modelFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { throw ServiceError.notDownloaded }
        let prompt = Self.prompt(transcript: transcript, styling: styling, structure: structure, context: context)
        let maxTokens = Int(Double(transcript.utf8.count / 3) * 1.3) + 48
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.runner == nil {
                        let start = Date()
                        self.runner = try LlamaRunner(modelPath: path)
                        self.logger.info("S1-mini loaded in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
                    }
                    let start = Date()
                    let output = try self.runner!.complete(prompt: prompt, maxTokens: max(maxTokens, 32))
                    self.logger.info("S1-mini normalized \(transcript.count) chars in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
                    continuation.resume(returning: Self.cleanOutput(output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func unload() {
        queue.async { self.runner = nil }
    }

    /// Blocking release, used at app termination.
    func unloadSync() {
        queue.sync { self.runner = nil }
        LlamaRunner.shutdownBackend()
    }

    /// Loads the GGUF into memory ahead of the first request.
    func preload() async {
        let path = S1MiniModelManager.modelFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        await withCheckedContinuation { continuation in
            queue.async {
                if self.runner == nil {
                    let start = Date()
                    self.runner = try? LlamaRunner(modelPath: path)
                    self.logger.info("S1-mini preloaded in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
                }
                continuation.resume()
            }
        }
    }

    static func prompt(transcript: String, styling: Styling, structure: Structure, context: Context) -> String {
        let user = "[Styling: \(styling.rawValue)] [Structure: \(structure.rawValue)] [Context: \(context.rawValue)]\n\(transcript)"
        return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    private static func cleanOutput(_ output: String) -> String {
        var text = output
        if let range = text.range(of: "</think>") { text = String(text[range.upperBound...]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
