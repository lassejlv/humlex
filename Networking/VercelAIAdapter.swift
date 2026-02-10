import Foundation

struct VercelAIAdapter: LLMProviderAdapter {
    let provider: AIProvider = .vercelAI

    // Vercel AI Gateway base URL
    private let baseURL = "https://ai-gateway.vercel.sh/v1"

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(VercelAIModelsResponse.self, from: data)
        let models = decoded.data.map {
            LLMModel(provider: provider, modelID: $0.id, displayName: $0.id)
        }

        return models.sorted(by: compareModels)
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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

// MARK: - Vercel AI Models Response

struct VercelAIModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
    }

    let data: [ModelData]
}
