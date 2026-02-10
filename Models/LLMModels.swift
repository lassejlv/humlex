import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case openRouter = "OpenRouter"
    case vercelAI = "Vercel AI"
    case gemini = "Gemini"

    var id: String { rawValue }

    var keychainAccount: String {
        switch self {
        case .openAI:
            return "openai_api_key"
        case .anthropic:
            return "anthropic_api_key"
        case .openRouter:
            return "openrouter_api_key"
        case .vercelAI:
            return "vercel_ai_api_key"
        case .gemini:
            return "gemini_api_key"
        }
    }
}

enum ChatRole: String, Hashable {
    case system
    case user
    case assistant
}

struct LLMChatMessage: Hashable {
    let role: ChatRole
    let content: String
    let attachments: [Attachment]

    init(role: ChatRole, content: String, attachments: [Attachment] = []) {
        self.role = role
        self.content = content
        self.attachments = attachments
    }
}

struct LLMModel: Identifiable, Hashable {
    let provider: AIProvider
    let modelID: String
    let displayName: String

    var id: String { reference }

    var reference: String {
        "\(provider.rawValue)::\(modelID)"
    }
}

protocol LLMProviderAdapter {
    var provider: AIProvider { get }
    func fetchModels(apiKey: String) async throws -> [LLMModel]
    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws
}

enum AdapterError: LocalizedError {
    case invalidResponse
    case missingResponseText
    case api(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The API returned an invalid response."
        case .missingResponseText:
            return "The model returned an empty response."
        case .api(let message):
            return message
        }
    }
}
