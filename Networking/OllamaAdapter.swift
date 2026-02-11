import Foundation

struct OllamaAdapter: LLMProviderAdapter {
    let provider: AIProvider = .ollama

    private let baseURL = "http://localhost:11434"

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/tags")!)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateOllamaHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        let models = decoded.models.map {
            LLMModel(provider: provider, modelID: $0.name, displayName: $0.name)
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
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let toolDefs = ollamaToolDefs(from: tools)
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

private func ollamaToolDefs(from mcpTools: [MCPTool]) -> [[String: AnyCodable]]? {
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

private func validateOllamaHTTPResponse(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
        if let envelope = try? JSONDecoder().decode(OllamaErrorEnvelope.self, from: data),
           !envelope.error.isEmpty {
            throw AdapterError.api(message: envelope.error)
        }
        throw AdapterError.api(message: "Request failed with status \(http.statusCode).")
    }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct OllamaErrorEnvelope: Decodable {
    let error: String
}
