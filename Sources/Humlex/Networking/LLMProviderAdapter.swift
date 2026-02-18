import Foundation

// MARK: - Shared Helpers

func compareModels(_ lhs: LLMModel, _ rhs: LLMModel) -> Bool {
    if lhs.modelID.hasPrefix("gpt") && !rhs.modelID.hasPrefix("gpt") { return true }
    if !lhs.modelID.hasPrefix("gpt") && rhs.modelID.hasPrefix("gpt") { return false }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}

func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
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

/// Stream SSE with tool call support (OpenAI-compatible format).
/// Returns a StreamResult with accumulated text and any tool calls.
func streamSSE(
    bytes: URLSession.AsyncBytes,
    response: URLResponse,
    onEvent: @escaping @Sendable (StreamEvent) async -> Void
) async throws -> StreamResult {
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
    var fullText = ""
    // Track tool calls being assembled from stream deltas
    var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]
    // Track usage from the final chunk (if present)
    var finalUsage: TokenUsage?

    for try await line in bytes.lines {
        try Task.checkCancellation()

        guard line.hasPrefix("data:") else { continue }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" { break }
        guard let data = payload.data(using: .utf8) else { continue }

        if let chunk = try? decoder.decode(OpenAIChatStreamChunk.self, from: data) {
            // Check for usage information (typically in final chunk)
            if let usage = chunk.usage {
                finalUsage = TokenUsage(
                    inputTokens: usage.promptTokens,
                    outputTokens: usage.completionTokens,
                    totalTokens: usage.totalTokens
                )
            }
            
            if let choice = chunk.choices.first {
                // Handle text content
                if let text = choice.delta.contentText, !text.isEmpty {
                    emittedAny = true
                    fullText += text
                    await onEvent(.textDelta(text))
                }

                // Handle tool calls
                if let toolCalls = choice.delta.toolCalls {
                    for tc in toolCalls {
                        let idx = tc.index
                        if let id = tc.id, let name = tc.function?.name {
                            // New tool call starting
                            toolCallAccumulators[idx] = (id: id, name: name, arguments: "")
                            await onEvent(.toolCallStart(index: idx, id: id, name: name))
                        }
                        if let argDelta = tc.function?.arguments, !argDelta.isEmpty {
                            toolCallAccumulators[idx]?.arguments += argDelta
                            await onEvent(.toolCallArgumentDelta(index: idx, delta: argDelta))
                        }
                    }
                    emittedAny = true
                }
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

    // Build tool calls from accumulators
    let toolCalls = toolCallAccumulators.sorted(by: { $0.key < $1.key }).map { (_, acc) in
        ToolCallInfo(id: acc.id, name: acc.name, arguments: acc.arguments, serverName: "")
    }

    await onEvent(.done)
    return StreamResult(text: fullText, toolCalls: toolCalls, usage: finalUsage)
}

func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
        data.append(byte)
    }
    return data
}

/// Build an API message from an LLMChatMessage, converting attachments to
/// the multimodal content-parts format when needed.
func apiMessage(from msg: LLMChatMessage) -> OpenAIChatStreamRequest.Message {
    typealias M = OpenAIChatStreamRequest.Message
    typealias P = M.ContentPart

    // Tool result messages
    if msg.role == .tool, let toolResult = msg.toolResult {
        return M(
            role: "tool",
            content: .text(toolResult.content),
            toolCallID: toolResult.toolCallID,
            toolCalls: nil
        )
    }

    // Assistant messages with tool calls
    if msg.role == .assistant && !msg.toolCalls.isEmpty {
        let tcObjects = msg.toolCalls.map { tc in
            M.ToolCallObject(
                id: tc.id,
                type: "function",
                function: M.ToolCallObject.FunctionObject(
                    name: tc.name,
                    arguments: tc.arguments
                )
            )
        }
        return M(
            role: "assistant",
            content: msg.content.isEmpty ? nil : .text(msg.content),
            toolCallID: nil,
            toolCalls: tcObjects
        )
    }

    // No attachments -> plain text (cheaper, wider model support)
    guard !msg.attachments.isEmpty else {
        return M(role: msg.role.rawValue, content: .text(msg.content), toolCallID: nil, toolCalls: nil)
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

    return M(role: msg.role.rawValue, content: .parts(parts), toolCallID: nil, toolCalls: nil)
}

/// Convert MCP tools to OpenAI tool format for the request body.
func openAIToolDefinitions(from mcpTools: [MCPTool]) -> [[String: Any]]? {
    guard !mcpTools.isEmpty else { return nil }
    return mcpTools.map { tool in
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.inputSchema.mapValues { $0.value }
            ] as [String: Any]
        ] as [String: Any]
    }
}

// MARK: - OpenAI Shared Codable Types

struct OpenAIChatStreamRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: MessageContent?
        let toolCallID: String?
        let toolCalls: [ToolCallObject]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCallID = "tool_call_id"
            case toolCalls = "tool_calls"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
            try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        }

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

        struct ToolCallObject: Encodable {
            let id: String
            let type: String
            let function: FunctionObject

            struct FunctionObject: Encodable {
                let name: String
                let arguments: String
            }
        }
    }

    let model: String
    let stream: Bool
    let messages: [Message]
    let tools: [[String: AnyCodable]]?

    init(model: String, stream: Bool, messages: [Message], tools: [[String: AnyCodable]]? = nil) {
        self.model = model
        self.stream = stream
        self.messages = messages
        self.tools = tools
    }
}

struct OpenAIChatStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ContentPart: Decodable {
                let text: String?
            }

            struct ToolCall: Decodable {
                let index: Int
                let id: String?
                let type: String?
                let function: Function?

                struct Function: Decodable {
                    let name: String?
                    let arguments: String?
                }
            }

            let content: String?
            let contentParts: [ContentPart]?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
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

                toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            }

            var contentText: String? {
                if let content, !content.isEmpty { return content }
                let joined = (contentParts ?? []).compactMap { $0.text }.joined()
                return joined.isEmpty ? nil : joined
            }
        }

        let delta: Delta
    }
    
    /// Token usage information (only present in the final chunk of the stream)
    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    let choices: [Choice]
    let usage: Usage?
}

struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
