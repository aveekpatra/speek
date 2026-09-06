import Testing
import Foundation
@testable import Speek

/// Regression cover for the "Czech kept transcribing as English" bug: a mode must not be
/// silently pinned to English, the one-time migration must undo any existing "en" pin, and
/// the Soniox config must always carry the language hints + context.general rescue.
struct CzechLanguageFixTests {

    // MARK: - ModeConfig no longer coalesces nil to "en"

    @Test func modeConfigKeepsNilLanguage() {
        let config = ModeConfig(name: "Test", isAIEnhancementEnabled: false)
        #expect(config.selectedLanguage == nil)

        let explicitNil = ModeConfig(name: "Test", isAIEnhancementEnabled: false, selectedLanguage: nil)
        #expect(explicitNil.selectedLanguage == nil)
    }

    // MARK: - Migration nulls an "en" pin, leaves everything else alone

    @Test func migrationClearsEnglishPinButLeavesOthers() {
        let english = ModeConfig(name: "A", isAIEnhancementEnabled: false, selectedLanguage: "en")
        let german = ModeConfig(name: "B", isAIEnhancementEnabled: false, selectedLanguage: "de")
        let unpinned = ModeConfig(name: "C", isAIEnhancementEnabled: false, selectedLanguage: nil)

        let migrated = ModeManager.clearingEnglishLanguagePins([english, german, unpinned])

        #expect(migrated[0].selectedLanguage == nil)   // "en" cleared to auto/hints
        #expect(migrated[1].selectedLanguage == "de")  // deliberate choice untouched
        #expect(migrated[2].selectedLanguage == nil)   // already unpinned, untouched
    }

    // MARK: - Global "SelectedLanguage" key is normalized ("en" is no signal)

    @Test func normalizedGlobalLanguageTreatsEnglishAsAuto() {
        #expect(ModeManager.normalizedGlobalLanguage("en") == "auto")   // bogus pin -> auto
        #expect(ModeManager.normalizedGlobalLanguage(nil) == "auto")    // unset -> auto
        #expect(ModeManager.normalizedGlobalLanguage("auto") == "auto") // already auto
        #expect(ModeManager.normalizedGlobalLanguage("de") == "de")     // real choice kept
    }

    // MARK: - Soniox config payload

    private func general(in payload: [String: Any]) -> [[String: String]]? {
        (payload["context"] as? [String: Any])?["general"] as? [[String: String]]
    }

    private func value(for key: String, in payload: [String: Any]) -> String? {
        general(in: payload)?.first { $0["key"] == key }?["value"]
    }

    @Test func autoHintsTreatFirstLanguageAsPrimary() {
        let payload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "auto",
            customVocabulary: [], preferredHints: ["cs", "en"]
        )

        #expect(payload["language_hints"] as? [String] == ["cs", "en"])
        #expect(payload["language_hints_strict"] as? Bool == true)
        #expect(value(for: "language", in: payload) == "Czech")

        let instructions = value(for: "instructions", in: payload)
        #expect(instructions?.contains("primarily speaks Czech") == true)
        #expect(instructions?.contains("English") == true)
        #expect(instructions?.contains("prefer Czech") == true)
    }

    /// Soniox's own docs warn `enable_language_identification` misclassifies the first few
    /// words of a stream (too little context) — exactly the "Czech opens in English" bug.
    /// Language is already pinned via language_hints + context.general, so this key must
    /// never be sent.
    @Test func payloadNeverEnablesLanguageIdentification() {
        let autoPayload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "auto",
            customVocabulary: [], preferredHints: ["cs", "en"]
        )
        #expect(autoPayload["enable_language_identification"] == nil)

        let pinnedPayload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "cs",
            customVocabulary: [], preferredHints: ["cs", "en"]
        )
        #expect(pinnedPayload["enable_language_identification"] == nil)
    }

    @Test func concreteLanguageOutputsOnlyThatLanguage() {
        let payload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "cs",
            customVocabulary: [], preferredHints: ["cs", "en"]
        )

        #expect(payload["language_hints"] as? [String] == ["cs"])
        #expect(payload["language_hints_strict"] as? Bool == true)
        #expect(value(for: "instructions", in: payload) == "Output the transcription only in Czech.")
    }

    /// A mode can pin any Soniox language, not just the 12 Settings chips, so the display name
    /// must resolve through the full LanguageDictionary (e.g. "ja" -> "Japanese"), not degrade
    /// to the raw code.
    @Test func concreteLanguageResolvesFullDictionaryName() {
        let payload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "ja",
            customVocabulary: [], preferredHints: ["cs", "en"]
        )

        #expect(value(for: "language", in: payload) == "Japanese")
        #expect(value(for: "instructions", in: payload) == "Output the transcription only in Japanese.")
    }

    @Test func customVocabularyAddsTermsAlongsideGeneral() {
        let payload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "auto",
            customVocabulary: ["Soniox", "Whisper"], preferredHints: ["cs", "en"]
        )

        let context = payload["context"] as? [String: Any]
        #expect(context?["terms"] as? [String] == ["Soniox", "Whisper"])
        #expect(general(in: payload) != nil)
    }

    @Test func emptyVocabularyOmitsTermsButKeepsGeneral() {
        let payload = SonioxRealtimeClient.makeConfigPayload(
            apiKey: "k", model: "m", language: "auto",
            customVocabulary: [], preferredHints: ["cs", "en"]
        )

        let context = payload["context"] as? [String: Any]
        #expect(context?["terms"] == nil)
        #expect(general(in: payload) != nil)
    }
}
