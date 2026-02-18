import Foundation

/// Stores API keys in a JSON file under Application Support/Humlex.
/// Replaces the macOS Keychain approach to avoid password prompts with unsigned builds.
enum KeychainStore {
    private static let fileName = "secrets.json"

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Humlex")
        return appDir.appendingPathComponent(fileName)
    }

    static func loadString(for key: String) throws -> String? {
        let store = try loadStore()
        return store[key]
    }

    static func saveString(_ value: String, for key: String) throws {
        var store = (try? loadStore()) ?? [:]
        store[key] = value
        try saveStore(store)
    }

    static func deleteValue(for key: String) throws {
        var store = (try? loadStore()) ?? [:]
        store.removeValue(forKey: key)
        try saveStore(store)
    }

    // MARK: - Private

    private static func loadStore() throws -> [String: String] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static func saveStore(_ store: [String: String]) throws {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: url, options: [.atomic])

        // Set file permissions to owner-only read/write (600)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain error (\(status))."
        }
    }
}
