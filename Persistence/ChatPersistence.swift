import Foundation

// MARK: - Chat Index Entry

/// Lightweight metadata for a chat thread, stored in the index file.
/// Contains everything needed for the sidebar without loading messages.
struct ChatIndexEntry: Codable, Identifiable {
    let id: UUID
    var title: String
    var agentEnabled: Bool
    var dangerousMode: Bool
    var workingDirectory: String?
    var messageCount: Int
    var lastModified: Date

    init(from thread: ChatThread) {
        self.id = thread.id
        self.title = thread.title
        self.agentEnabled = thread.agentEnabled
        self.dangerousMode = thread.dangerousMode
        self.workingDirectory = thread.workingDirectory
        self.messageCount = thread.messages.count
        self.lastModified = thread.messages.last?.timestamp ?? .now
    }

    // Backward-compatible decoding
    enum CodingKeys: String, CodingKey {
        case id, title, agentEnabled, dangerousMode, workingDirectory, messageCount, lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        agentEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentEnabled) ?? false
        dangerousMode = try container.decodeIfPresent(Bool.self, forKey: .dangerousMode) ?? false
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? .now
    }
}

// MARK: - Chat Persistence (one file per chat)

enum ChatPersistence {
    private static let folderName = "Humlex"
    private static let chatsDirName = "chats"
    private static let indexFileName = "index.json"
    private static let legacyFileName = "chats.json"

    // MARK: - Directory helpers

    private static func appSupportDir() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func chatsDir() throws -> URL {
        let dir = try appSupportDir().appendingPathComponent(chatsDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func indexURL() throws -> URL {
        try chatsDir().appendingPathComponent(indexFileName)
    }

    private static func chatFileURL(for id: UUID) throws -> URL {
        try chatsDir().appendingPathComponent("\(id.uuidString).json")
    }

    private static func legacyFileURL() throws -> URL {
        try appSupportDir().appendingPathComponent(legacyFileName)
    }

    // MARK: - Shared encoder/decoder

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Migration from legacy single-file format

    /// Checks for the old monolithic `chats.json` and migrates to per-chat files.
    /// Returns true if migration occurred.
    @discardableResult
    static func migrateIfNeeded() throws -> Bool {
        let legacy = try legacyFileURL()
        guard FileManager.default.fileExists(atPath: legacy.path) else { return false }

        let data = try Data(contentsOf: legacy)

        // Use a lenient decoder for legacy data (no iso8601 dates — legacy used default)
        let legacyDecoder = JSONDecoder()
        let threads = try legacyDecoder.decode([ChatThread].self, from: data)

        guard !threads.isEmpty else {
            // Empty file — just remove it
            try? FileManager.default.removeItem(at: legacy)
            return false
        }

        // Write each thread as a separate file
        for thread in threads {
            try saveThread(thread)
        }

        // Write the index
        let entries = threads.map { ChatIndexEntry(from: $0) }
        try saveIndex(entries)

        // Remove legacy file
        try FileManager.default.removeItem(at: legacy)

        return true
    }

    // MARK: - Index operations

    /// Load the chat index (lightweight, no messages).
    static func loadIndex() throws -> [ChatIndexEntry] {
        let url = try indexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([ChatIndexEntry].self, from: data)
    }

    /// Save the chat index.
    static func saveIndex(_ entries: [ChatIndexEntry]) throws {
        let url = try indexURL()
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Per-chat operations

    /// Load a single chat thread by ID (includes all messages).
    static func loadThread(id: UUID) throws -> ChatThread? {
        let url = try chatFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ChatThread.self, from: data)
    }

    /// Save a single chat thread.
    static func saveThread(_ thread: ChatThread) throws {
        let url = try chatFileURL(for: thread.id)
        let dir = try chatsDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(thread)
        try data.write(to: url, options: .atomic)
    }

    /// Delete a single chat thread file.
    static func deleteThread(id: UUID) throws {
        let url = try chatFileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Bulk operations (for backward compat / initial load)

    /// Load all threads fully (loads index, then each chat file).
    static func loadAll() throws -> [ChatThread] {
        let entries = try loadIndex()
        var threads: [ChatThread] = []
        for entry in entries {
            if let thread = try loadThread(id: entry.id) {
                threads.append(thread)
            }
        }
        return threads
    }

    /// Legacy load — only used for migration detection.
    static func load() throws -> [ChatThread]? {
        // First try new format
        let index = try loadIndex()
        if !index.isEmpty {
            return try loadAll()
        }
        // Fall back to legacy (will be migrated)
        return nil
    }

    /// Legacy save — no longer used, kept for reference.
    static func save(_ threads: [ChatThread]) throws {
        for thread in threads {
            try saveThread(thread)
        }
        let entries = threads.map { ChatIndexEntry(from: $0) }
        try saveIndex(entries)
    }
}
