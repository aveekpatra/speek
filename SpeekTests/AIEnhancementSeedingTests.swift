import Testing
import Foundation
import SwiftData
@testable import Speek

@MainActor
struct AIEnhancementSeedingTests {

    /// Regression test: on a real installed app, UserDefaults has no "customPrompts" key
    /// (zero prompts ever saved). Turning the AI Enhancement toggle on used to silently
    /// no-op because no prompt existed, so isConfigured stayed false forever.
    @Test func enablingAIEnhancementOnAFreshInstallResolvesAConfiguredPrompt() async throws {
        // Simulates a fresh install by clearing customPrompts, but this key holds the
        // user's real saved prompts on this machine, so it must always be restored.
        let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts")
        defer {
            if let savedPromptsData {
                UserDefaults.standard.set(savedPromptsData, forKey: "customPrompts")
            } else {
                UserDefaults.standard.removeObject(forKey: "customPrompts")
            }
        }
        UserDefaults.standard.removeObject(forKey: "customPrompts")

        // repairModePromptSelections() (called from AIEnhancementService.init below) rewrites
        // ModeManager.shared.configurations whenever a mode points at a prompt id that no
        // longer exists (true here, since customPrompts was just wiped), and persists that
        // under "modeConfigurationsV2". Back up and restore both the UserDefaults value and
        // the in-memory singleton, so the user's real mode/prompt selection survives this test
        // even if it fails partway through.
        let savedModeConfigData = UserDefaults.standard.data(forKey: "modeConfigurationsV2")
        let originalModeConfigurations = savedModeConfigData
            .flatMap { try? JSONDecoder().decode([ModeConfig].self, from: $0) } ?? []
        defer {
            if let savedModeConfigData {
                UserDefaults.standard.set(savedModeConfigData, forKey: "modeConfigurationsV2")
            } else {
                UserDefaults.standard.removeObject(forKey: "modeConfigurationsV2")
            }
            ModeManager.shared.configurations = originalModeConfigurations
        }

        let container = try ModelContainer(
            for: Schema([Transcription.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let enhancementService = AIEnhancementService(modelContext: container.mainContext)

        #expect(!enhancementService.allPrompts.isEmpty)

        let cleanPrompt = enhancementService.allPrompts.first { $0.id == PromptTemplates.cleanPromptId }
        #expect(cleanPrompt != nil)

        // This mirrors what repairModePromptSelections() assigns when the toggle turns on
        // for a mode that has no prompt yet: it falls back to the first available prompt.
        let fallbackPromptId = enhancementService.allPrompts.first?.id
        #expect(fallbackPromptId == cleanPrompt?.id)

        let configuration = EnhancementRuntimeConfiguration(
            mode: nil,
            isEnabled: true,
            prompt: cleanPrompt,
            provider: .localCLI,
            modelName: nil,
            useClipboardContext: false,
            useSelectedTextContext: false,
            useScreenCaptureContext: false
        )

        #expect(enhancementService.isConfigured(for: configuration))
    }

    /// Regression test: Groq's default enhancement model must be openai/gpt-oss-120b
    /// (matching AIProvider.defaultModel), not availableModels.first (llama-3.1-8b-instant),
    /// when the mode has no explicitly selected model.
    ///
    /// This calls the resolver's decision function directly (provider already given,
    /// no selected model) instead of going through currentEnhancementConfiguration's
    /// "is this provider connected" check, so the test never needs a real Groq API key
    /// in the Keychain: a previous version wrote a fake key there and could leave it
    /// behind, clobbering the user's actual key.
    @Test func groqEnhancementModelFallsBackToProviderDefaultNotFirstAvailableModel() async throws {
        let aiService = AIService()

        let modelName = ModeRuntimeResolver.resolvedEnhancementModelName(
            provider: .groq,
            configuredModelName: nil,
            aiService: aiService
        )

        #expect(modelName == "openai/gpt-oss-120b")
    }
}
