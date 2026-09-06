import Foundation
import llama
import os

/// Minimal llama.cpp wrapper: loads a GGUF once, runs greedy completions.
final class LlamaRunner {
    enum RunnerError: LocalizedError {
        case modelLoadFailed(String)
        case contextFailed
        case tokenizeFailed
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let path): return "Could not load the model at \(path)."
            case .contextFailed: return "Could not create a llama context."
            case .tokenizeFailed: return "Could not tokenize the prompt."
            case .decodeFailed: return "The model failed while decoding."
            }
        }
    }

    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let contextSize: Int32
    private let logger = Logger(subsystem: "com.aveekpatra.speek", category: "LlamaRunner")
    private static let backendInit: Void = { llama_backend_init() }()

    init(modelPath: String, contextSize: Int32 = 4096) throws {
        _ = Self.backendInit
        llama_log_set({ _, _, _ in }, nil)
        var params = llama_model_default_params()
        params.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(modelPath, params) else {
            throw RunnerError.modelLoadFailed(modelPath)
        }
        self.model = model
        self.vocab = llama_model_get_vocab(model)
        self.contextSize = contextSize
    }

    deinit {
        llama_model_free(model)
    }

    /// Tears the ggml backends down explicitly so the process can exit cleanly.
    static func shutdownBackend() {
        llama_backend_free()
    }

    /// Greedy completion of `prompt` (already formatted with the chat template).
    func complete(prompt: String, maxTokens: Int) throws -> String {
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = 512
        contextParams.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        contextParams.n_threads_batch = contextParams.n_threads
        guard let context = llama_init_from_model(model, contextParams) else {
            throw RunnerError.contextFailed
        }
        defer { llama_free(context) }

        let promptUTF8 = Array(prompt.utf8)
        var tokens = [llama_token](repeating: 0, count: promptUTF8.count + 16)
        let count = promptUTF8.withUnsafeBufferPointer { buffer -> Int32 in
            buffer.withMemoryRebound(to: CChar.self) { chars in
                llama_tokenize(vocab, chars.baseAddress, Int32(promptUTF8.count), &tokens, Int32(tokens.count), false, true)
            }
        }
        guard count > 0 else { throw RunnerError.tokenizeFailed }
        tokens.removeSubrange(Int(count)...)

        var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        guard llama_decode(context, batch) == 0 else { throw RunnerError.decodeFailed }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        defer { llama_sampler_free(sampler) }

        var output = ""
        var pieceBuffer = [CChar](repeating: 0, count: 256)
        var generated = 0
        var nextToken: llama_token = 0
        while generated < maxTokens {
            nextToken = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, nextToken) { break }
            let length = llama_token_to_piece(vocab, nextToken, &pieceBuffer, Int32(pieceBuffer.count), 0, true)
            if length > 0 {
                let bytes = pieceBuffer[0..<Int(length)].map { UInt8(bitPattern: $0) }
                output += String(decoding: bytes, as: UTF8.self)
            }
            generated += 1
            batch = llama_batch_get_one(&nextToken, 1)
            guard llama_decode(context, batch) == 0 else { break }
        }
        return output
    }
}
