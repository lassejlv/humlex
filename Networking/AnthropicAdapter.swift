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
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract system message if present
        let systemMessage = history.first { $0.role == .system }?.content
        let conversationHistory = history.filter { $0.role != .system }

        let toolDefs = anthropicToolDefs(from: tools)
        let body = AnthropicMessagesRequest(
            model: modelID,
            max_tokens: 8192,
            system: systemMessage,
            stream: true,
            messages: conversationHistory.map { anthropicMessage(from: $0) },
            tools: toolDefs
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        return try await streamAnthropicSSE(bytes: bytes, response: response, onEvent: onEvent)
    }
}

private func anthropicMessage(from msg: LLMChatMessage) -> AnthropicMessagesRequest.Message {
    typealias M = AnthropicMessagesRequest.Message
    typealias C = M.Content

    let role = msg.role == .user ? "user" : (msg.role == .tool ? "user" : "assistant")

    // Tool result messages — sent as user messages with tool_result content blocks
    if msg.role == .tool, let toolResult = msg.toolResult {
        let block = C.ContentBlock.toolResult(
            toolUseId: toolResult.toolCallID,
            content: toolResult.content,
            isError: toolResult.isError
        )
        return M(role: "user", content: .blocks([block]))
    }

    // Assistant messages with tool calls
    if msg.role == .assistant && !msg.toolCalls.isEmpty {
        var blocks: [C.ContentBlock] = []
        if !msg.content.isEmpty {
            blocks.append(.text(msg.content))
        }
        for tc in msg.toolCalls {
            // Parse arguments JSON string into a dict
            let inputDict: [String: Any]
            if let data = tc.arguments.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                inputDict = dict
            } else {
                inputDict = [:]
            }
            blocks.append(.toolUse(id: tc.id, name: tc.name, input: inputDict))
        }
        return M(role: "assistant", content: .blocks(blocks))
    }

    // No attachments -> plain text
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
    onEvent: @escaping @Sendable (StreamEvent) async -> Void
) async throws -> StreamResult {
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
    var fullText = ""
    // Track tool use blocks being assembled
    var currentToolUseIndex = 0
    var toolUseAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]
    // Track usage from the final message (if present)
    var finalUsage: TokenUsage?

    for try await line in bytes.lines {
        try Task.checkCancellation()

        guard line.hasPrefix("data:") else { continue }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { continue }

        if let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) {
            switch event.type {
            case "content_block_start":
                if let contentBlock = event.contentBlock {
                    if contentBlock.type == "tool_use" {
                        let id = contentBlock.id ?? ""
                        let name = contentBlock.name ?? ""
                        toolUseAccumulators[currentToolUseIndex] = (id: id, name: name, arguments: "")
                        await onEvent(.toolCallStart(index: currentToolUseIndex, id: id, name: name))
                        emittedAny = true
                    }
                }

            case "content_block_delta":
                if let delta = event.delta {
                    if delta.type == "text_delta", let text = delta.text, !text.isEmpty {
                        emittedAny = true
                        fullText += text
                        await onEvent(.textDelta(text))
                    } else if delta.type == "input_json_delta", let partial = delta.partialJson, !partial.isEmpty {
                        toolUseAccumulators[currentToolUseIndex]?.arguments += partial
                        await onEvent(.toolCallArgumentDelta(index: currentToolUseIndex, delta: partial))
                        emittedAny = true
                    }
                }

            case "content_block_stop":
                currentToolUseIndex += 1

            case "message_stop":
                // Message complete - check for usage if available
                if let usage = event.usage {
                    finalUsage = TokenUsage(
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens,
                        totalTokens: usage.inputTokens + usage.outputTokens
                    )
                }

            default:
                break
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

    let toolCalls = toolUseAccumulators.sorted(by: { $0.key < $1.key }).map { (_, acc) in
        ToolCallInfo(id: acc.id, name: acc.name, arguments: acc.arguments, serverName: "")
    }

    await onEvent(.done)
    return StreamResult(text: fullText, toolCalls: toolCalls, usage: finalUsage)
}

private func anthropicToolDefs(from mcpTools: [MCPTool]) -> [AnthropicToolDefinition]? {
    guard !mcpTools.isEmpty else { return nil }
    return mcpTools.map { tool in
        AnthropicToolDefinition(
            name: tool.name,
            description: tool.description,
            input_schema: AnyCodable(tool.inputSchema.mapValues { $0.value })
        )
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

struct AnthropicToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: AnyCodable
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
                case toolUse(id: String, name: String, input: [String: Any])
                case toolResult(toolUseId: String, content: String, isError: Bool)

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
                    case .toolUse(let id, let name, let input):
                        try container.encode("tool_use", forKey: .type)
                        try container.encode(id, forKey: .id)
                        try container.encode(name, forKey: .name)
                        try container.encode(AnyCodable(input), forKey: .input)
                    case .toolResult(let toolUseId, let content, let isError):
                        try container.encode("tool_result", forKey: .type)
                        try container.encode(toolUseId, forKey: .toolUseId)
                        try container.encode(content, forKey: .content)
                        if isError {
                            try container.encode(true, forKey: .isError)
                        }
                    }
                }

                private enum CodingKeys: String, CodingKey {
                    case type, text, source, id, name, input
                    case toolUseId = "tool_use_id"
                    case content
                    case isError = "is_error"
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
    let tools: [AnthropicToolDefinition]?
}

struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let contentBlock: ContentBlock?
    let usage: Usage?

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partialJson: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJson = "partial_json"
        }
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
    }
    
    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, delta
        case contentBlock = "content_block"
        case usage
    }
}

struct AnthropicErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
