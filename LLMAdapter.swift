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
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
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

private func compareModels(_ lhs: LLMModel, _ rhs: LLMModel) -> Bool {
    if lhs.modelID.hasPrefix("gpt") && !rhs.modelID.hasPrefix("gpt") { return true }
    if !lhs.modelID.hasPrefix("gpt") && rhs.modelID.hasPrefix("gpt") { return false }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}

private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
        if let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
        throw AdapterError.api(message: "Request failed with status \(http.statusCode).")
    }
}

private func streamSSE(
    bytes: URLSession.AsyncBytes,
    response: URLResponse,
    onDelta: @escaping @Sendable (String) async -> Void
) async throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }

    if !(200...299).contains(http.statusCode) {
        let data = try await collectData(from: bytes)
        if let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
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

        if payload == "[DONE]" { break }
        guard let data = payload.data(using: .utf8) else { continue }

        if let chunk = try? decoder.decode(OpenAIChatStreamChunk.self, from: data) {
            if let delta = chunk.choices.first?.delta.contentText, !delta.isEmpty {
                emittedAny = true
                await onDelta(delta)
            }
            continue
        }

        if let apiError = try? decoder.decode(OpenAIErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
    }

    if !emittedAny {
        throw AdapterError.missingResponseText
    }
}

private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
        data.append(byte)
    }
    return data
}

private struct OpenAIModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
    }

    let data: [ModelData]
}

private struct OpenRouterModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
        let name: String?
    }

    let data: [ModelData]
}

private struct VercelAIModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
    }

    let data: [ModelData]
}

private struct OpenAIChatStreamRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: MessageContent

        enum MessageContent: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
        }

        enum ContentPart: Encodable {
            case text(String)
            case imageURL(url: String)

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .imageURL(let url):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(ImageURL(url: url), forKey: .image_url)
                }
            }

            private enum CodingKeys: String, CodingKey {
                case type, text, image_url
            }

            private struct ImageURL: Encodable {
                let url: String
            }
        }
    }

    let model: String
    let stream: Bool
    let messages: [Message]
}

/// Build an API message from an LLMChatMessage, converting attachments to
/// the multimodal content-parts format when needed.
private func apiMessage(from msg: LLMChatMessage) -> OpenAIChatStreamRequest.Message {
    typealias M = OpenAIChatStreamRequest.Message
    typealias P = M.ContentPart

    // No attachments → plain text (cheaper, wider model support)
    guard !msg.attachments.isEmpty else {
        return M(role: msg.role.rawValue, content: .text(msg.content))
    }

    var parts: [P] = []

    // Add text file contents inline before the user text
    for att in msg.attachments where att.isText {
        parts.append(.text("--- File: \(att.fileName) ---\n\(att.content)\n--- End of \(att.fileName) ---"))
    }

    // Add images as data URLs
    for att in msg.attachments where att.isImage {
        let dataURL = "data:\(att.mimeType);base64,\(att.content)"
        parts.append(.imageURL(url: dataURL))
    }

    // Add non-text, non-image files as a mention
    for att in msg.attachments where !att.isText && !att.isImage {
        parts.append(.text("[Attached file: \(att.fileName) (\(att.fileSizeLabel))]"))
    }

    // Add user text last
    if !msg.content.isEmpty {
        parts.append(.text(msg.content))
    }

    return M(role: msg.role.rawValue, content: .parts(parts))
}

private struct OpenAIChatStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ContentPart: Decodable {
                let text: String?
            }

            let content: String?
            let contentParts: [ContentPart]?

            enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                if let plain = try? container.decodeIfPresent(String.self, forKey: .content) {
                    content = plain
                    contentParts = nil
                } else if let parts = try? container.decodeIfPresent(
                    [ContentPart].self,
                    forKey: .content
                ) {
                    content = nil
                    contentParts = parts
                } else {
                    content = nil
                    contentParts = nil
                }
            }

            var contentText: String? {
                if let content, !content.isEmpty { return content }
                let joined = (contentParts ?? []).compactMap { $0.text }.joined()
                return joined.isEmpty ? nil : joined
            }
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

// MARK: - Gemini Adapter

struct GeminiAdapter: LLMProviderAdapter {
    let provider: AIProvider = .gemini

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        var request = URLRequest(url: URL(string: "\(baseURL)/models?key=\(apiKey)")!)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGeminiHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let models = decoded.models
            .filter { $0.supportedGenerationMethods.contains("generateContent") }
            .map { model -> LLMModel in
                // model.name is like "models/gemini-2.0-flash" — strip the prefix for the ID
                let modelID = model.name.hasPrefix("models/")
                    ? String(model.name.dropFirst("models/".count))
                    : model.name
                return LLMModel(
                    provider: provider,
                    modelID: modelID,
                    displayName: model.displayName
                )
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
        let url = URL(
            string: "\(baseURL)/models/\(modelID):streamGenerateContent?alt=sse&key=\(apiKey)"
        )!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiStreamRequest(
            contents: history.map { geminiContent(from: $0) }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await streamGeminiSSE(bytes: bytes, response: response, onDelta: onDelta)
    }
}

/// Build a Gemini content object from an LLMChatMessage, converting attachments.
private func geminiContent(from msg: LLMChatMessage) -> GeminiStreamRequest.Content {
    typealias Part = GeminiStreamRequest.Content.Part

    // Gemini uses "user" and "model" (not "assistant")
    let role = msg.role == .user ? "user" : "model"

    var parts: [Part] = []

    // Add text file contents inline
    for att in msg.attachments where att.isText {
        parts.append(.init(
            text: "--- File: \(att.fileName) ---\n\(att.content)\n--- End of \(att.fileName) ---",
            inlineData: nil
        ))
    }

    // Add images as inline data
    for att in msg.attachments where att.isImage {
        parts.append(.init(
            text: nil,
            inlineData: .init(mimeType: att.mimeType, data: att.content)
        ))
    }

    // Add non-text, non-image files as a mention
    for att in msg.attachments where !att.isText && !att.isImage {
        parts.append(.init(
            text: "[Attached file: \(att.fileName) (\(att.fileSizeLabel))]",
            inlineData: nil
        ))
    }

    // Add user text
    if !msg.content.isEmpty {
        parts.append(.init(text: msg.content, inlineData: nil))
    }

    // Ensure at least one part (Gemini requires non-empty parts)
    if parts.isEmpty {
        parts.append(.init(text: "", inlineData: nil))
    }

    return .init(role: role, parts: parts)
}

private func streamGeminiSSE(
    bytes: URLSession.AsyncBytes,
    response: URLResponse,
    onDelta: @escaping @Sendable (String) async -> Void
) async throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }

    if !(200...299).contains(http.statusCode) {
        let data = try await collectData(from: bytes)
        if let apiError = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) {
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

        if payload == "[DONE]" { break }
        guard let data = payload.data(using: .utf8) else { continue }

        if let chunk = try? decoder.decode(GeminiStreamChunk.self, from: data) {
            for candidate in chunk.candidates ?? [] {
                for part in candidate.content?.parts ?? [] {
                    if let text = part.text, !text.isEmpty {
                        emittedAny = true
                        await onDelta(text)
                    }
                }
            }
            continue
        }

        if let apiError = try? decoder.decode(GeminiErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
    }

    if !emittedAny {
        throw AdapterError.missingResponseText
    }
}

private func validateGeminiHTTPResponse(_ response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
        throw AdapterError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
        if let apiError = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) {
            throw AdapterError.api(message: apiError.error.message)
        }
        throw AdapterError.api(message: "Request failed with status \(http.statusCode).")
    }
}

// MARK: - Gemini Codable Structs

private struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let displayName: String
        let supportedGenerationMethods: [String]
    }

    let models: [Model]
}

private struct GeminiStreamRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?

            struct InlineData: Encodable {
                let mimeType: String
                let data: String
            }
        }

        let role: String
        let parts: [Part]
    }

    let contents: [Content]
}

private struct GeminiStreamChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]?
        }

        let content: Content?
    }

    let candidates: [Candidate]?
}

private struct GeminiErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

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

private struct AnthropicModelsResponse: Decodable {
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

private struct AnthropicMessagesRequest: Encodable {
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

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

private struct AnthropicErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
