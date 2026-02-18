import Foundation

struct OpenAICompatibleAdapter: LLMProviderAdapter {
    let provider: AIProvider = .openAICompatible
    let baseURLString: String

    init(baseURLString: String) {
        self.baseURLString = baseURLString
    }

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: try endpointURL(path: "models"))
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(normalizedBearerToken(apiKey))", forHTTPHeaderField: "Authorization")

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
        var request = URLRequest(url: try endpointURL(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(normalizedBearerToken(apiKey))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let toolDefs = openAICompatibleToolDefs(from: tools)
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

    private func endpointURL(path: String) throws -> URL {
        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty else {
            throw AdapterError.api(message: "Missing OpenAI Compatible API endpoint.")
        }
        guard let baseURL = URL(string: trimmedBase), let scheme = baseURL.scheme,
            scheme == "http" || scheme == "https"
        else {
            throw AdapterError.api(
                message: "Invalid OpenAI Compatible API endpoint. Use http:// or https://.")
        }

        let normalizedPath = baseURL.path.hasSuffix("/v1") ? path : "v1/\(path)"
        guard let endpoint = URL(string: "\(trimmedBase)/\(normalizedPath)") else {
            throw AdapterError.api(message: "Failed to build request URL from endpoint.")
        }
        return endpoint
    }

    private func normalizedBearerToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("bearer ".count)).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        return trimmed
    }
}

private func openAICompatibleToolDefs(from mcpTools: [MCPTool]) -> [[String: AnyCodable]]? {
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
