import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case openRouter = "OpenRouter"
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

struct LLMModel: Identifiable, Hashable {
    let provider: AIProvider
    let modelID: String
    let displayName: String

    var id: String { reference }

    var reference: String {
        "\(provider.rawValue)::\(modelID)"
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

/// The result of a completed streaming response.
struct StreamResult {
    let text: String
    let toolCalls: [ToolCallInfo]
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
