import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case openRouter = "OpenRouter"
    case fastRouter = "FastRouter"
    case vercelAI = "Vercel AI"
    case gemini = "Gemini"
    case kimi = "Kimi for Coding"
    case ollama = "Ollama"
    case claudeCode = "Claude Code"
    case openAICodex = "OpenAI Codex"

    var id: String { rawValue }

    var keychainAccount: String {
        switch self {
        case .openAI:
            return "openai_api_key"
        case .anthropic:
            return "anthropic_api_key"
        case .openRouter:
            return "openrouter_api_key"
        case .fastRouter:
            return "fastrouter_api_key"
        case .vercelAI:
            return "vercel_ai_api_key"
        case .gemini:
            return "gemini_api_key"
        case .kimi:
            return "kimi_api_key"
        case .ollama:
            return "ollama_config"
        case .claudeCode:
            return "claude_code_config"
        case .openAICodex:
            return "openai_codex_config"
        }
    }

    /// Whether this provider requires a traditional API key.
    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .claudeCode, .openAICodex: return false
        default: return true
        }
    }
}

enum ChatRole: String, Hashable {
    case system
    case user
    case assistant
    case tool
}

/// Represents a tool call request from the LLM.
struct ToolCallInfo: Hashable {
    let id: String
    let name: String
    let arguments: String  // JSON string of arguments
    let serverName: String  // MCP server that owns this tool
    let thoughtSignature: String?

    init(
        id: String, name: String, arguments: String, serverName: String,
        thoughtSignature: String? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.serverName = serverName
        self.thoughtSignature = thoughtSignature
    }
}

/// Represents the result of executing a tool call.
struct ToolResultInfo: Hashable {
    let toolCallID: String
    let toolName: String
    let content: String
    let isError: Bool
}

struct LLMChatMessage: Hashable {
    let role: ChatRole
    let content: String
    let attachments: [Attachment]
    let toolCalls: [ToolCallInfo]  // Non-empty when assistant requests tool calls
    let toolResult: ToolResultInfo?  // Non-nil when role == .tool

    init(
        role: ChatRole, content: String, attachments: [Attachment] = [],
        toolCalls: [ToolCallInfo] = [], toolResult: ToolResultInfo? = nil
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
        self.toolCalls = toolCalls
        self.toolResult = toolResult
    }
}

/// Model specifications including context window and output limits.
struct ModelSpecs: Hashable, Sendable {
    let contextWindow: Int
    let maxOutputTokens: Int?
    
    init(contextWindow: Int, maxOutputTokens: Int? = nil) {
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
}

/// Registry of known model specifications.
enum ModelRegistry {
    /// Known models and their specifications.
    static let knownModels: [String: ModelSpecs] = [
        // OpenAI
        "gpt-4o": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 16_384),
        "gpt-4o-latest": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 16_384),
        "gpt-4o-2024-08-06": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 16_384),
        "gpt-4o-2024-05-13": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 4_096),
        "gpt-4o-mini": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 16_384),
        "gpt-4o-mini-latest": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 16_384),
        "gpt-4-turbo": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 4_096),
        "gpt-4-turbo-preview": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 4_096),
        "gpt-4": ModelSpecs(contextWindow: 8_192),
        "gpt-4-32k": ModelSpecs(contextWindow: 32_768),
        "gpt-3.5-turbo": ModelSpecs(contextWindow: 16_385),
        "o1": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 100_000),
        "o1-mini": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 65_536),
        "o3-mini": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 100_000),
        
        // Anthropic
        "claude-3-5-sonnet-latest": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 8_192),
        "claude-3-5-sonnet-20241022": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 8_192),
        "claude-3-5-sonnet-20240620": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 8_192),
        "claude-3-opus-latest": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 4_096),
        "claude-3-opus-20240229": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 4_096),
        "claude-3-sonnet-20240229": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 4_096),
        "claude-3-haiku-20240307": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 4_096),
        "claude-3-5-haiku-latest": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 8_192),
        
        // Gemini
        "gemini-2.0-flash": ModelSpecs(contextWindow: 1_048_576, maxOutputTokens: 8_192),
        "gemini-2.0-flash-thinking": ModelSpecs(contextWindow: 1_048_576, maxOutputTokens: 8_192),
        "gemini-1.5-pro": ModelSpecs(contextWindow: 2_097_152, maxOutputTokens: 8_192),
        "gemini-1.5-pro-latest": ModelSpecs(contextWindow: 2_097_152, maxOutputTokens: 8_192),
        "gemini-1.5-flash": ModelSpecs(contextWindow: 1_048_576, maxOutputTokens: 8_192),
        "gemini-1.5-flash-latest": ModelSpecs(contextWindow: 1_048_576, maxOutputTokens: 8_192),
        
        // Default fallbacks by provider
        "__openai_default__": ModelSpecs(contextWindow: 128_000, maxOutputTokens: 4_096),
        "__anthropic_default__": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 4_096),
        "__gemini_default__": ModelSpecs(contextWindow: 1_048_576, maxOutputTokens: 8_192),
        "__kimi_default__": ModelSpecs(contextWindow: 200_000, maxOutputTokens: 8_192),
    ]
    
    /// Get specs for a model ID, falling back to provider defaults if not known.
    static func specs(for modelID: String, provider: AIProvider) -> ModelSpecs {
        if let specs = knownModels[modelID] {
            return specs
        }
        
        // Try provider-specific defaults
        switch provider {
        case .openAI, .openRouter, .fastRouter, .vercelAI:
            return knownModels["__openai_default__"]!
        case .anthropic:
            return knownModels["__anthropic_default__"]!
        case .gemini:
            return knownModels["__gemini_default__"]!
        case .kimi:
            return knownModels["__kimi_default__"]!
        case .ollama, .claudeCode, .openAICodex:
            // Ollama and CLI providers - use a conservative default
            return ModelSpecs(contextWindow: 128_000, maxOutputTokens: 4_096)
        }
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
    
    /// The context window size for this model (in tokens).
    var contextWindow: Int {
        ModelRegistry.specs(for: modelID, provider: provider).contextWindow
    }
    
    /// The maximum output tokens for this model, if known.
    var maxOutputTokens: Int? {
        ModelRegistry.specs(for: modelID, provider: provider).maxOutputTokens
    }
}

/// Represents a structured streaming event from the LLM.
enum StreamEvent: Sendable {
    case textDelta(String)
    case toolCallStart(index: Int, id: String, name: String)
    case toolCallArgumentDelta(index: Int, delta: String)
    /// Informational tool usage from CLI providers (already executed, display only).
    case cliToolUse(id: String, name: String, arguments: String, serverName: String)
    case done
}

/// Token usage information from an API response.
struct TokenUsage: Hashable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    var remainingTokens: Int { max(0, totalTokens - outputTokens) }
}

/// The result of a completed streaming response.
struct StreamResult {
    let text: String
    let toolCalls: [ToolCallInfo]
    let usage: TokenUsage?
    
    init(text: String, toolCalls: [ToolCallInfo] = [], usage: TokenUsage? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

protocol LLMProviderAdapter {
    var provider: AIProvider { get }
    func fetchModels(apiKey: String) async throws -> [LLMModel]

    /// Stream a message with optional tool definitions.
    /// Returns a StreamResult containing the full text and any tool calls.
    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult
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
