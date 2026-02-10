import Foundation

// MARK: - Anthropic Adapter

struct AnthropicAdapter: LLMProviderAdapter {
    let provider: AIProvider = .anthropic

    private let baseURL = "https://api.anthropic.com/v1"
    private let apiVersion = "2023-06-01"

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAnthropicHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        let models = decoded.data.map {
            LLMModel(provider: provider, modelID: $0.id, displayName: $0.displayName ?? $0.id)
        }

        return models.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract system message if present
        let systemMessage = history.first { $0.role == .system }?.content
        let conversationHistory = history.filter { $0.role != .system }

        let body = AnthropicMessagesRequest(
            model: modelID,
            max_tokens: 8192,
            system: systemMessage,
            stream: true,
            messages: conversationHistory.map { anthropicMessage(from: $0) }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await streamAnthropicSSE(bytes: bytes, response: response, onDelta: onDelta)
    }
}

private func anthropicMessage(from msg: LLMChatMessage) -> AnthropicMessagesRequest.Message {
    typealias M = AnthropicMessagesRequest.Message
    typealias C = M.Content

    let role = msg.role == .user ? "user" : "assistant"

    // No attachments → plain text
    guard !msg.attachments.isEmpty else {
        return M(role: role, content: .text(msg.content))
    }

    var parts: [C.ContentBlock] = []

    // Add text file contents inline
    for att in msg.attachments where att.isText {
        parts.append(.text("--- File: \(att.fileName) ---\n\(att.content)\n--- End of \(att.fileName) ---"))
    }

    // Add images
    for att in msg.attachments where att.isImage {
        parts.append(.image(mediaType: att.mimeType, data: att.content))
    }

    // Add non-text, non-image files as a mention
    for att in msg.attachments where !att.isText && !att.isImage {
        parts.append(.text("[Attached file: \(att.fileName) (\(att.fileSizeLabel))]"))
    }

    // Add user text last
    if !msg.content.isEmpty {
        parts.append(.text(msg.content))
    }

    return M(role: role, content: .blocks(parts))
}

private func streamAnthropicSSE(
    bytes: URLSession.AsyncBytes,
    response: URLResponse,
    onDelta: @escaping @Sendable (String) async -> Void
) async throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }

    if !(200...299).contains(http.statusCode) {
        let data = try await collectData(from: bytes)
        if let apiError = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
        throw AdapterError.api(message: "Request failed with status \(http.statusCode).")
    }

    var emittedAny = false
    let decoder = JSONDecoder()

    for try await line in bytes.lines {
        try Task.checkCancellation()

        guard line.hasPrefix("data:") else { continue }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { continue }

        if let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) {
            if event.type == "content_block_delta",
               let delta = event.delta,
               delta.type == "text_delta",
               let text = delta.text, !text.isEmpty {
                emittedAny = true
                await onDelta(text)
            }
            continue
        }

        if let apiError = try? decoder.decode(AnthropicErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
    }

    if !emittedAny {
        throw AdapterError.missingResponseText
    }
}

private func validateAnthropicHTTPResponse(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
        if let apiError = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
        throw AdapterError.api(message: "Request failed with status \(http.statusCode).")
    }
}

// MARK: - Anthropic Codable Structs

struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    let data: [Model]
}

struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        enum Content: Encodable {
            case text(String)
            case blocks([ContentBlock])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .blocks(let blocks):
                    try container.encode(blocks)
                }
            }

            enum ContentBlock: Encodable {
                case text(String)
                case image(mediaType: String, data: String)

                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                    case .text(let text):
                        try container.encode("text", forKey: .type)
                        try container.encode(text, forKey: .text)
                    case .image(let mediaType, let data):
                        try container.encode("image", forKey: .type)
                        try container.encode(
                            ImageSource(type: "base64", media_type: mediaType, data: data),
                            forKey: .source
                        )
                    }
                }

                private enum CodingKeys: String, CodingKey {
                    case type, text, source
                }

                private struct ImageSource: Encodable {
                    let type: String
                    let media_type: String
                    let data: String
                }
            }
        }

        let role: String
        let content: Content
    }

    let model: String
    let max_tokens: Int
    let system: String?
    let stream: Bool
    let messages: [Message]
}

struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

struct AnthropicErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
