import Foundation

struct OpenAIAdapter: LLMProviderAdapter {
    let provider: AIProvider = .openAI

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        let models = decoded.data.map {
            LLMModel(provider: provider, modelID: $0.id, displayName: $0.id)
        }

        return models.sorted(by: compareModels)
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let toolDefs = openAIToolDefs(from: tools)
        let body = OpenAIChatStreamRequest(
            model: modelID,
            stream: true,
            messages: history.map { apiMessage(from: $0) },
            tools: toolDefs
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        return try await streamSSE(bytes: bytes, response: response, onEvent: onEvent)
    }
}

/// Convert MCP tools to OpenAI tool format as AnyCodable array.
private func openAIToolDefs(from mcpTools: [MCPTool]) -> [[String: AnyCodable]]? {
    guard !mcpTools.isEmpty else { return nil }
    return mcpTools.map { tool in
        [
            "type": AnyCodable("function"),
            "function": AnyCodable([
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.inputSchema.mapValues { $0.value }
            ] as [String: Any])
        ]
    }
}

// MARK: - OpenAI Models Response

struct OpenAIModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
    }

    let data: [ModelData]
}
