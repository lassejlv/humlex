import Foundation

struct ChatThread: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
}

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Hashable, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date
    var attachments: [Attachment]

    init(id: UUID, role: Role, text: String, timestamp: Date, attachments: [Attachment] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachments = attachments
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
