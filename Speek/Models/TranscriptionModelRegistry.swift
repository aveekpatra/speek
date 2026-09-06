import Foundation

enum TranscriptionModelRegistry {

    static var models: [any TranscriptionModel] {
        return predefinedModels
    }
    
    private static let predefinedModels: [any TranscriptionModel] = {
        let nonCloudModels: [any TranscriptionModel] = [
            // Native Apple Model
            NativeAppleModel(
                name: "apple-speech",
                displayName: "Apple Speech",
                description: "Uses the native Apple Speech framework for transcription. Requires macOS 26",
                isMultilingualModel: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .nativeApple)
            ),

            // Cohere Transcribe (open weights, 14 languages)
            CohereModel(
                name: CohereModelManager.modelName,
                displayName: "Cohere Transcribe",
                description: "Cohere's open 2B speech model: top of the Open ASR leaderboard, 14 languages. This CoreML build always encodes a 35 s window, so expect about 4 to 6 s per dictation and a few minutes of one-time compile per launch. Pick Parakeet V3 for instant results.",
                size: "2.1 GB",
                speed: 0.85,
                accuracy: 0.99,
                ramUsage: 2.6,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .cohere)
            ),

            // NVIDIA Canary 1B v2 (25 European languages)
            CanaryModel(
                name: CanaryModelManager.modelName,
                displayName: "Canary 1B v2",
                description: "NVIDIA's Canary 1B v2: excellent accuracy across 25 European languages, int4 on the Neural Engine.",
                size: "1.1 GB",
                speed: 0.8,
                accuracy: 0.97,
                ramUsage: 1.6,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .canary)
            ),

            // NVIDIA Parakeet (FluidAudio)
            FluidAudioModel(
                name: "parakeet-tdt-0.6b-v3",
                displayName: "Parakeet V3",
                description: "Parakeet V3: near-instant results (well under a second), English and 25 European languages. The best default for dictation.",
                size: "494 MB",
                speed: 0.99,
                accuracy: 0.94,
                ramUsage: 0.8,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .fluidAudio)
            ),
            FluidAudioModel(
                name: "parakeet-tdt-0.6b-v2",
                displayName: "Parakeet V2",
                description: "Parakeet V2: lightning-fast English-only transcription with the best recall.",
                size: "474 MB",
                speed: 0.99,
                accuracy: 0.94,
                ramUsage: 0.8,
                supportsStreaming: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .fluidAudio)
            ),
            FluidAudioModel(
                name: "parakeet-tdt-ctc-110m",
                displayName: "Parakeet 110M",
                description: "Tiny 110M English model: instant results on any Apple silicon Mac, lower accuracy.",
                size: "120 MB",
                speed: 1.0,
                accuracy: 0.85,
                ramUsage: 0.3,
                supportsStreaming: false,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .fluidAudio)
            ),
            FluidAudioModel(
                name: "parakeet-tdt-0.6b-ja",
                displayName: "Parakeet Japanese",
                description: "Parakeet 0.6B tuned for Japanese.",
                size: "500 MB",
                speed: 0.98,
                accuracy: 0.93,
                ramUsage: 0.8,
                supportsStreaming: false,
                supportedLanguages: ["ja": "Japanese"]
            ),

            // OpenAI Whisper (whisper.cpp): a speed / accuracy ladder
            WhisperModel(
                name: "ggml-small",
                displayName: "Small",
                size: "466 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Fast tier: about twice the speed of Turbo, 99 languages, lower accuracy.",
                speed: 0.9,
                accuracy: 0.8,
                ramUsage: 0.7
            ),
            WhisperModel(
                name: "ggml-small.en",
                displayName: "Small (English)",
                size: "466 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .whisper),
                description: "Fast tier tuned for English only.",
                speed: 0.9,
                accuracy: 0.83,
                ramUsage: 0.7
            ),
            WhisperModel(
                name: "ggml-distil-large-v3",
                displayName: "Distil Large v3 (English)",
                size: "1.5 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .whisper),
                description: "Distilled Large v3 for English: Turbo-class speed with better English accuracy.",
                speed: 0.78,
                accuracy: 0.96,
                ramUsage: 1.8,
                downloadBaseURL: "https://huggingface.co/distil-whisper/distil-large-v3-ggml/resolve/main/"
            ),
            WhisperModel(
                name: "ggml-large-v3-turbo",
                displayName: "Large v3 Turbo",
                size: "1.5 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Balanced tier: the best speed-to-accuracy Whisper, 99 languages.",
                speed: 0.75,
                accuracy: 0.97,
                ramUsage: 1.8
            ),
            WhisperModel(
                name: "ggml-large-v3",
                displayName: "Large v3",
                size: "2.9 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Accurate tier: slowest Whisper, highest accuracy, best with accents and noise.",
                speed: 0.3,
                accuracy: 0.98,
                ramUsage: 3.9
            ),
            WhisperModel(
                name: "ggml-large-v3-turbo-q5_0",
                displayName: "Large v3 Turbo (Quantized)",
                size: "547 MB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Quantized Turbo for 8 GB Macs: a third of the size, slightly lower accuracy.",
                speed: 0.78,
                accuracy: 0.95,
                ramUsage: 1.0
            ),
            WhisperModel(
                name: "ggml-large-v3-q5_0",
                displayName: "Large v3 (Quantized)",
                size: "1.1 GB",
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper),
                description: "Quantized Large v3: most of the accuracy at a third of the size.",
                speed: 0.35,
                accuracy: 0.97,
                ramUsage: 1.5
            )
        ]

        // Speek is local-only: no cloud speech providers are registered.
        return nonCloudModels
    }()
}
