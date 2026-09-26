import Foundation
import LLMkit

extension AIService {
    func completeChat(
        provider: AIProvider,
        modelName: String?,
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let selectedProvider: AIProvider
        let resolvedModel: String
        if provider == .ollama || provider == .s1Mini ||
            (provider == .openAI && !ActionCredentials.hasKey(for: .openAI)) ||
            (provider == .openRouter && !ActionCredentials.hasKey(for: .openRouter)) {
            guard let cloud = ActionCredentials.activeProvider else { throw EnhancementError.notConfigured }
            selectedProvider = cloud == .openAI ? .openAI : .openRouter
            resolvedModel = cloud == .openAI ? "gpt-4o-mini" : "openai/gpt-4o-mini"
        } else {
            selectedProvider = provider
            resolvedModel = modelName?.isEmpty == false ? modelName! : selectedModel(for: provider)
        }

        let result: String
        switch selectedProvider {
        case .anthropic:
            result = try await AnthropicLLMClient.chatCompletion(
                apiKey: try chatAPIKey(for: selectedProvider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                timeout: timeout
            )
        case .custom:
            guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: resolvedModel),
                  let baseURL = URL(string: customConfiguration.baseURL) else {
                throw EnhancementError.notConfigured
            }
            result = try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: customConfiguration.apiKey,
                model: customConfiguration.modelName,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: 0.3,
                timeout: timeout
            )
        case .ollama, .s1Mini:
            throw EnhancementError.notConfigured
        case .localCLI:
            result = try await enhanceWithLocalCLI(
                systemPrompt: systemPrompt ?? "",
                userPrompt: chatPrompt(from: messages)
            )
        default:
            guard let baseURL = URL(string: selectedProvider.baseURL) else {
                throw EnhancementError.notConfigured
            }
            let temperature = resolvedModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
            let reasoningEffort = ReasoningConfig.getReasoningParameter(
                for: selectedProvider,
                modelName: resolvedModel
            )
            let extraBody = ReasoningConfig.getExtraBodyParameters(
                for: selectedProvider,
                modelName: resolvedModel
            )
            result = try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: try chatAPIKey(for: selectedProvider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: temperature,
                reasoningEffort: reasoningEffort,
                extraBody: extraBody,
                timeout: timeout
            )
        }

        return AIEnhancementOutputFilter.filter(result)
    }

    private func chatAPIKey(for provider: AIProvider, modelName: String) throws -> String {
        if provider == .custom {
            guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName) else {
                throw EnhancementError.notConfigured
            }
            return customConfiguration.apiKey
        }

        let key: String?
        if provider == .openAI { key = ActionCredentials.key(for: .openAI) }
        else if provider == .openRouter { key = ActionCredentials.key(for: .openRouter) }
        else { key = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue) }
        guard let key, !key.isEmpty else {
            throw EnhancementError.notConfigured
        }
        return key
    }

    private func chatPrompt(from messages: [ChatMessage]) -> String {
        let formattedMessages = messages.map { message in
            let label: String
            switch message.role {
            case "assistant":
                label = "assistant"
            case "user":
                label = "user"
            case "system":
                label = "system"
            default:
                label = "other"
            }
            return """
            <message role="\(label)">
            \(message.content)
            </message>
            """
        }
        .joined(separator: "\n\n")

        return """
        <conversation>
        \(formattedMessages)
        </conversation>
        """
    }
}
