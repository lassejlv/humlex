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
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        let url = URL(
            string: "\(baseURL)/models/\(modelID):streamGenerateContent?alt=sse&key=\(apiKey)"
        )!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let geminiTools = geminiToolDefs(from: tools)
        let body = GeminiStreamRequest(
            contents: buildGeminiContents(from: history),
            tools: geminiTools
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        return try await streamGeminiSSE(bytes: bytes, response: response, onEvent: onEvent)
    }
}

/// Build Gemini contents from LLMChatMessage history.
/// Gemini requires:
///   - "user" messages with text parts
///   - "model" messages with text and/or functionCall parts
///   - "user" messages with functionResponse parts for tool results
/// Tool result messages (.tool role) must be grouped and sent as functionResponse
/// parts in a single "user" content entry.
private func buildGeminiContents(from history: [LLMChatMessage]) -> [GeminiStreamRequest.Content] {
    typealias Part = GeminiStreamRequest.Content.Part
    typealias Content = GeminiStreamRequest.Content

    var contents: [Content] = []
    var pendingToolResponses: [Part] = []

    for msg in history {
        switch msg.role {
        case .system:
            // Gemini doesn't have a system role — prepend as user message
            if !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !pendingToolResponses.isEmpty {
                    contents.append(Content(role: "user", parts: pendingToolResponses))
                    pendingToolResponses = []
                }
                contents.append(Content(role: "user", parts: [
                    Part(text: msg.content, inlineData: nil, functionCall: nil, functionResponse: nil)
                ]))
            }

        case .user:
            // Flush any pending tool responses before the user message
            if !pendingToolResponses.isEmpty {
                contents.append(Content(role: "user", parts: pendingToolResponses))
                pendingToolResponses = []
            }
            contents.append(geminiContent(from: msg))

        case .assistant:
            // Flush any pending tool responses before the assistant message
            if !pendingToolResponses.isEmpty {
                contents.append(Content(role: "user", parts: pendingToolResponses))
                pendingToolResponses = []
            }

            var parts: [Part] = []

            // Add text content if present
            let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                parts.append(Part(text: text, inlineData: nil, functionCall: nil, functionResponse: nil))
            }

            // Add functionCall parts for any tool calls the model made
            for tc in msg.toolCalls {
                let argsDict: [String: AnyCodable]
                if let data = tc.arguments.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    argsDict = dict.mapValues { AnyCodable($0) }
                } else {
                    argsDict = [:]
                }

                // Some older chat history may not have thought signatures persisted.
                // Gemini rejects functionCall parts without thoughtSignature, so fall
                // back to plain text context instead of sending invalid parts.
                guard let thoughtSignature = tc.thoughtSignature, !thoughtSignature.isEmpty else {
                    parts.append(Part(
                        text: "[Previous tool call: \(tc.name) with args \(tc.arguments)]",
                        inlineData: nil,
                        functionCall: nil,
                        functionResponse: nil
                    ))
                    continue
                }

                parts.append(Part(
                    text: nil,
                    inlineData: nil,
                    functionCall: Part.FunctionCallPart(name: tc.name, args: argsDict),
                    functionResponse: nil,
                    thoughtSignature: thoughtSignature
                ))
            }

            // Ensure at least one part
            if parts.isEmpty {
                parts.append(Part(text: "", inlineData: nil, functionCall: nil, functionResponse: nil))
            }

            contents.append(Content(role: "model", parts: parts))

        case .tool:
            // Collect tool results as functionResponse parts.
            // These will be flushed as a single "user" content entry before the next message.
            guard let toolResult = msg.toolResult else { continue }

            let responseContent: [String: Any] = [
                "result": msg.content
            ]
            pendingToolResponses.append(Part(
                text: nil,
                inlineData: nil,
                functionCall: nil,
                functionResponse: Part.FunctionResponsePart(
                    name: toolResult.toolName,
                    response: AnyCodable(responseContent)
                )
            ))
        }
    }

    // Flush any remaining tool responses at the end (before LLM generates next response)
    if !pendingToolResponses.isEmpty {
        contents.append(Content(role: "user", parts: pendingToolResponses))
    }

    return contents
}

/// Build a Gemini content object from an LLMChatMessage, converting attachments.
/// Used only for user messages (assistant/tool messages are handled in buildGeminiContents).
private func geminiContent(from msg: LLMChatMessage) -> GeminiStreamRequest.Content {
    typealias Part = GeminiStreamRequest.Content.Part

    // Gemini uses "user" and "model" (not "assistant")
    let role = msg.role == .user ? "user" : "model"

    var parts: [Part] = []

    // Add text file contents inline
    for att in msg.attachments where att.isText {
        parts.append(.init(
            text: "--- File: \(att.fileName) ---\n\(att.content)\n--- End of \(att.fileName) ---",
            inlineData: nil,
            functionCall: nil,
            functionResponse: nil
        ))
    }

    // Add images as inline data
    for att in msg.attachments where att.isImage {
        parts.append(.init(
            text: nil,
            inlineData: .init(mimeType: att.mimeType, data: att.content),
            functionCall: nil,
            functionResponse: nil
        ))
    }

    // Add non-text, non-image files as a mention
    for att in msg.attachments where !att.isText && !att.isImage {
        parts.append(.init(
            text: "[Attached file: \(att.fileName) (\(att.fileSizeLabel))]",
            inlineData: nil,
            functionCall: nil,
            functionResponse: nil
        ))
    }

    // Add user text
    if !msg.content.isEmpty {
        parts.append(.init(text: msg.content, inlineData: nil, functionCall: nil, functionResponse: nil))
    }

    // Ensure at least one part (Gemini requires non-empty parts)
    if parts.isEmpty {
        parts.append(.init(text: "", inlineData: nil, functionCall: nil, functionResponse: nil))
    }

    return .init(role: role, parts: parts)
}

private func streamGeminiSSE(
    bytes: URLSession.AsyncBytes,
    response: URLResponse,
    onEvent: @escaping @Sendable (StreamEvent) async -> Void
) async throws -> StreamResult {
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
    var fullText = ""
    var toolCalls: [ToolCallInfo] = []
    var toolCallIndex = 0

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
                        fullText += text
                        await onEvent(.textDelta(text))
                    }
                    if let fc = part.functionCall {
                        let id = "gemini-tc-\(toolCallIndex)"
                        let argsData = try? JSONSerialization.data(withJSONObject: fc.args ?? [:])
                        let argsString = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCalls.append(ToolCallInfo(
                            id: id,
                            name: fc.name,
                            arguments: argsString,
                            serverName: "",
                            thoughtSignature: part.thoughtSignature
                        ))
                        await onEvent(.toolCallStart(index: toolCallIndex, id: id, name: fc.name))
                        await onEvent(.toolCallArgumentDelta(index: toolCallIndex, delta: argsString))
                        toolCallIndex += 1
                        emittedAny = true
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

    await onEvent(.done)
    return StreamResult(text: fullText, toolCalls: toolCalls)
}

private func geminiToolDefs(from mcpTools: [MCPTool]) -> [GeminiStreamRequest.Tool]? {
    guard !mcpTools.isEmpty else { return nil }
    let declarations = mcpTools.map { tool in
        // Gemini's Schema object rejects several JSON-schema/OpenAPI keys,
        // so sanitize recursively (including nested items/properties).
        let rawParams = tool.inputSchema.mapValues { $0.value }
        let params = sanitizeGeminiSchema(rawParams) as? [String: Any] ?? [:]
        return GeminiStreamRequest.Tool.FunctionDeclaration(
            name: tool.name,
            description: tool.description,
            parameters: AnyCodable(params)
        )
    }
    return [GeminiStreamRequest.Tool(functionDeclarations: declarations)]
}

private func sanitizeGeminiSchema(_ value: Any) -> Any {
    if let dict = value as? [String: Any] {
        var cleaned: [String: Any] = [:]
        for (key, nestedValue) in dict {
            // Gemini does not accept these schema fields.
            if key == "$schema" ||
                key == "additionalProperties" ||
                key == "unevaluatedProperties" ||
                key == "patternProperties" ||
                key == "propertyNames" ||
                key == "dependentSchemas" ||
                key == "contains" ||
                key == "if" ||
                key == "then" ||
                key == "else"
            {
                continue
            }
            cleaned[key] = sanitizeGeminiSchema(nestedValue)
        }
        return cleaned
    }

    if let array = value as? [Any] {
        return array.map { sanitizeGeminiSchema($0) }
    }

    return value
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
            let functionCall: FunctionCallPart?
            let functionResponse: FunctionResponsePart?
            let thoughtSignature: String?

            enum CodingKeys: String, CodingKey {
                case text
                case inlineData
                case functionCall
                case functionResponse
                case thoughtSignature
            }

            init(
                text: String?,
                inlineData: InlineData?,
                functionCall: FunctionCallPart?,
                functionResponse: FunctionResponsePart?,
                thoughtSignature: String? = nil
            ) {
                self.text = text
                self.inlineData = inlineData
                self.functionCall = functionCall
                self.functionResponse = functionResponse
                self.thoughtSignature = thoughtSignature
            }

            struct InlineData: Encodable {
                let mimeType: String
                let data: String
            }

            struct FunctionCallPart: Encodable {
                let name: String
                let args: [String: AnyCodable]?
            }

            struct FunctionResponsePart: Encodable {
                let name: String
                let response: AnyCodable
            }
        }

        let role: String
        let parts: [Part]
    }

    struct Tool: Encodable {
        struct FunctionDeclaration: Encodable {
            let name: String
            let description: String
            let parameters: AnyCodable
        }

        let functionDeclarations: [FunctionDeclaration]
    }

    let contents: [Content]
    let tools: [Tool]?

    init(contents: [Content], tools: [Tool]? = nil) {
        self.contents = contents
        self.tools = tools
    }
}

struct GeminiStreamChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
                let functionCall: FunctionCall?
                let thoughtSignature: String?

                enum CodingKeys: String, CodingKey {
                    case text
                    case functionCall
                    case thoughtSignature
                    case thought_signature
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    text = try container.decodeIfPresent(String.self, forKey: .text)
                    functionCall = try container.decodeIfPresent(FunctionCall.self, forKey: .functionCall)
                    thoughtSignature = try container.decodeIfPresent(String.self, forKey: .thoughtSignature)
                        ?? container.decodeIfPresent(String.self, forKey: .thought_signature)
                }
            }

            let parts: [Part]?
        }

        let content: Content?
    }

    let candidates: [Candidate]?
}

struct GeminiFunctionCall: Decodable {
    let name: String
    let args: [String: AnyCodable]?
}

// Extension to decode functionCall in parts
extension GeminiStreamChunk.Candidate.Content.Part {
    struct FunctionCall: Decodable {
        let name: String
        let args: [String: Any]?

        enum CodingKeys: String, CodingKey {
            case name, args
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            if let argsAnyCodable = try container.decodeIfPresent(AnyCodable.self, forKey: .args) {
                args = argsAnyCodable.asDictionary
            } else {
                args = nil
            }
        }
    }
}

struct GeminiErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
