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

func streamSSE(
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

// MARK: - OpenAI Shared Codable Types

struct OpenAIChatStreamRequest: Encodable {
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

struct OpenAIChatStreamChunk: Decodable {
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

struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
