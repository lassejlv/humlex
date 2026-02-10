import Foundation

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

struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let displayName: String
        let supportedGenerationMethods: [String]
    }

    let models: [Model]
}

struct GeminiStreamRequest: Encodable {
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

struct GeminiStreamChunk: Decodable {
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

struct GeminiErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
