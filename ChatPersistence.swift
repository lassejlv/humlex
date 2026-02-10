import Foundation

enum ChatPersistence {
    private static let folderName = "Humlex"
    private static let fileName = "chats.json"

    static func load() throws -> [ChatThread]? {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ChatThread].self, from: data)
    }

    static func save(_ threads: [ChatThread]) throws {
        let directory = try directoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(threads)

        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
    }

    private static func fileURL() throws -> URL {
        try directoryURL().appendingPathComponent(fileName)
    }

    private static func directoryURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(folderName, isDirectory: true)
    }
}
