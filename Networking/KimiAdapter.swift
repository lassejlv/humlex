import Foundation

struct KimiAdapter: LLMProviderAdapter {
    let provider: AIProvider = .kimi
    var userAgent = "KimiCLI/1.3"

    private let baseURL = "https://api.kimi.com/coding/v1"
    private let defaultModelID = "kimi-for-coding"

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, data: data)

            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let models = decoded.data.map {
                LLMModel(provider: provider, modelID: $0.id, displayName: $0.id)
            }

            if models.isEmpty {
                return [
                    LLMModel(
                        provider: provider, modelID: defaultModelID, displayName: defaultModelID)
                ]
            }

            return models.sorted(by: compareModels)
        } catch {
            return [
                LLMModel(provider: provider, modelID: defaultModelID, displayName: defaultModelID)
            ]
        }
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let toolDefs = kimiToolDefs(from: tools)
        // let hasAssistantToolCallsInHistory = history.contains { !$0.toolCalls.isEmpty }
        let body = KimiChatStreamRequest(
            model: modelID.isEmpty ? defaultModelID : modelID,
            stream: true,
            messages: history.map { kimiMessage(from: $0) },
            tools: toolDefs,
            maxOutputTokens: 32_768,
            reasoningEffort: "medium"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        return try await streamSSE(bytes: bytes, response: response, onEvent: onEvent)
    }
}

private struct KimiChatStreamRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: OpenAIChatStreamRequest.Message.MessageContent?
        let toolCallID: String?
        let toolCalls: [OpenAIChatStreamRequest.Message.ToolCallObject]?
        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCallID = "tool_call_id"
            case toolCalls = "tool_calls"
            case reasoningContent = "reasoning_content"
        }
    }

    let model: String
    let stream: Bool
    let messages: [Message]
    let tools: [[String: AnyCodable]]?
    let maxOutputTokens: Int
    let reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case messages
        case tools
        case maxOutputTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }
}

private func kimiMessage(from message: LLMChatMessage) -> KimiChatStreamRequest.Message {
    let base = apiMessage(from: message)
    let isAssistantToolCallMessage = base.role == "assistant" && !(base.toolCalls?.isEmpty ?? true)

    return KimiChatStreamRequest.Message(
        role: base.role,
        content: base.content,
        toolCallID: base.toolCallID,
        toolCalls: base.toolCalls,
        reasoningContent: isAssistantToolCallMessage ? "tool-call reasoning context" : nil
    )
}

private func kimiToolDefs(from mcpTools: [MCPTool]) -> [[String: AnyCodable]]? {
    guard !mcpTools.isEmpty else { return nil }
    return mcpTools.map { tool in
        [
            "type": AnyCodable("function"),
            "function": AnyCodable(
                [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema.mapValues { $0.value },
                ] as [String: Any]),
        ]
    }
}
