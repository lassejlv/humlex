import Foundation
import Security

struct KeychainMigrationResult {
    let totalKeys: Int
    let migratedKeys: Int
    let skippedExistingKeys: Int
    let skippedEmptyKeys: Int
}

/// Stores secrets in the macOS Keychain.
enum KeychainStore {
    private static let service = "com.local.humlex"
    private static let legacyFileName = "secrets.json"

    static func loadString(for key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.invalidItemData
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func saveString(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainError.unhandledStatus(updateStatus)
        }
    }

    static func deleteValue(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func legacyStoreExists() -> Bool {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return false
        }
        guard let data = try? Data(contentsOf: legacyFileURL),
            let store = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return false
        }
        return !store.isEmpty
    }

    static func legacyStoreHasKeysMissingFromKeychain() throws -> Bool {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return false
        }

        let data = try Data(contentsOf: legacyFileURL)
        let store = try JSONDecoder().decode([String: String].self, from: data)

        for (key, rawValue) in store {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let existing = try loadString(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existing?.isEmpty != false {
                return true
            }
        }

        return false
    }

    static func migrateLegacyFileStoreToKeychain(removeLegacyFile: Bool = false) throws
        -> KeychainMigrationResult
    {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return KeychainMigrationResult(
                totalKeys: 0,
                migratedKeys: 0,
                skippedExistingKeys: 0,
                skippedEmptyKeys: 0
            )
        }

        let data = try Data(contentsOf: legacyFileURL)
        let store = try JSONDecoder().decode([String: String].self, from: data)

        var migrated = 0
        var skippedExisting = 0
        var skippedEmpty = 0

        for (key, rawValue) in store {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                skippedEmpty += 1
                continue
            }

            let existing = try loadString(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing, !existing.isEmpty {
                skippedExisting += 1
                continue
            }

            try saveString(value, for: key)
            migrated += 1
        }

        if removeLegacyFile {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }

        return KeychainMigrationResult(
            totalKeys: store.count,
            migratedKeys: migrated,
            skippedExistingKeys: skippedExisting,
            skippedEmptyKeys: skippedEmpty
        )
    }

    private static var legacyFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("Humlex")
        return appDir.appendingPathComponent(legacyFileName)
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)
    case invalidItemData

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain error (\(status))."
        case .invalidItemData:
            return "Keychain returned invalid item data."
        }
    }
}
