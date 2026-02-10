import Foundation

struct OpenRouterAdapter: LLMProviderAdapter {
    let provider: AIProvider = .openRouter

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        let models = decoded.data.map {
            LLMModel(provider: provider, modelID: $0.id, displayName: $0.name ?? $0.id)
        }

        return models.sorted(by: compareModels)
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://localhost", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Humlex", forHTTPHeaderField: "X-Title")

        let body = OpenAIChatStreamRequest(
            model: modelID,
            stream: true,
            messages: history.map { apiMessage(from: $0) }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await streamSSE(bytes: bytes, response: response, onDelta: onDelta)
    }
}

// MARK: - OpenRouter Models Response

struct OpenRouterModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
        let name: String?
    }

    let data: [ModelData]
}
