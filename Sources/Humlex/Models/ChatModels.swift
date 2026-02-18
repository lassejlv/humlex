import Foundation

struct ChatThread: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var agentEnabled: Bool
    var dangerousMode: Bool
    var workingDirectory: String?
    var systemPrompt: String?
    
    /// Token usage tracking for this thread
    var tokenUsage: ThreadTokenUsage?
    /// The model reference used for this thread (for context window tracking)
    var modelReference: String?

    init(id: UUID, title: String, messages: [ChatMessage], agentEnabled: Bool = false, dangerousMode: Bool = false, workingDirectory: String? = nil, systemPrompt: String? = nil, tokenUsage: ThreadTokenUsage? = nil, modelReference: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.agentEnabled = agentEnabled
        self.dangerousMode = dangerousMode
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt
        self.tokenUsage = tokenUsage
        self.modelReference = modelReference
    }

    // Custom Codable to handle missing keys from old persisted data
    enum CodingKeys: String, CodingKey {
        case id, title, messages, agentEnabled, dangerousMode, workingDirectory, systemPrompt, tokenUsage, modelReference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        agentEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentEnabled) ?? false
        dangerousMode = try container.decodeIfPresent(Bool.self, forKey: .dangerousMode) ?? false
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        tokenUsage = try container.decodeIfPresent(ThreadTokenUsage.self, forKey: .tokenUsage)
        modelReference = try container.decodeIfPresent(String.self, forKey: .modelReference)
    }
    
    /// Updates the token usage based on current messages and model
    mutating func updateTokenUsage(modelContextWindow: Int) {
        let estimatedTokens = TokenEstimator.estimateTotalTokens(for: messages)
        if var usage = tokenUsage {
            usage.updateEstimated(estimatedTokens)
            tokenUsage = usage
        } else {
            tokenUsage = ThreadTokenUsage(
                estimatedTokens: estimatedTokens,
                contextWindow: modelContextWindow
            )
        }
    }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Hashable, Codable {
        case user
        case assistant
        case tool
    }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date
    var attachments: [Attachment]

    // Tool-related fields (optional, for MCP integration)
    var toolCalls: [ToolCall]?      // When assistant requests tool calls
    var toolCallID: String?          // When role == .tool, the ID of the tool call this responds to
    var toolName: String?            // When role == .tool, the name of the tool

    init(id: UUID, role: Role, text: String, timestamp: Date, attachments: [Attachment] = [],
         toolCalls: [ToolCall]? = nil, toolCallID: String? = nil, toolName: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachments = attachments
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
    }

    /// A tool call requested by the assistant.
    struct ToolCall: Hashable, Codable {
        let id: String
        let name: String
        let arguments: String
        let serverName: String
        let thoughtSignature: String?

        init(id: String, name: String, arguments: String, serverName: String, thoughtSignature: String? = nil) {
            self.id = id
            self.name = name
            self.arguments = arguments
            self.serverName = serverName
            self.thoughtSignature = thoughtSignature
        }
    }
}

/// A file attached to a chat message.
struct Attachment: Identifiable, Hashable, Codable {
    let id: UUID
    let fileName: String
    let mimeType: String
    /// Base64-encoded file data for images; inline text content for text files.
    let content: String
    let fileSize: Int

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var isText: Bool {
        mimeType.hasPrefix("text/") ||
        mimeType == "application/json" ||
        mimeType == "application/xml" ||
        mimeType == "application/javascript" ||
        fileName.hasSuffix(".md") ||
        fileName.hasSuffix(".swift") ||
        fileName.hasSuffix(".py") ||
        fileName.hasSuffix(".rs") ||
        fileName.hasSuffix(".ts") ||
        fileName.hasSuffix(".tsx") ||
        fileName.hasSuffix(".jsx") ||
        fileName.hasSuffix(".js") ||
        fileName.hasSuffix(".css") ||
        fileName.hasSuffix(".html") ||
        fileName.hasSuffix(".yml") ||
        fileName.hasSuffix(".yaml") ||
        fileName.hasSuffix(".toml") ||
        fileName.hasSuffix(".sh") ||
        fileName.hasSuffix(".bash") ||
        fileName.hasSuffix(".c") ||
        fileName.hasSuffix(".cpp") ||
        fileName.hasSuffix(".h") ||
        fileName.hasSuffix(".go") ||
        fileName.hasSuffix(".rb") ||
        fileName.hasSuffix(".java") ||
        fileName.hasSuffix(".kt") ||
        fileName.hasSuffix(".sql") ||
        fileName.hasSuffix(".env") ||
        fileName.hasSuffix(".csv") ||
        fileName.hasSuffix(".log")
    }

    var fileSizeLabel: String {
        if fileSize < 1024 {
            return "\(fileSize) B"
        } else if fileSize < 1024 * 1024 {
            return "\(fileSize / 1024) KB"
        } else {
            return String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
        }
    }
}
