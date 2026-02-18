import Foundation

/// Detects the nvm-managed Node.js binary path so that
/// `ClaudeCodeClient` (which shells out to `claude`) can find the CLI
/// even when the app is launched outside a shell environment.
enum NvmPathDetector {
    /// Returns the path to the nvm `bin` directory for the default Node version, if available.
    /// e.g. `~/.nvm/versions/node/v20.11.0/bin`
    static func detectNvmPath() -> String? {
        let home = NSHomeDirectory()
        let nvmDir = (home as NSString).appendingPathComponent(".nvm/versions/node")

        let fm = FileManager.default
        guard fm.fileExists(atPath: nvmDir) else { return nil }

        // Try to read the default alias
        let aliasPath = (home as NSString).appendingPathComponent(".nvm/alias/default")
        if let alias = try? String(contentsOfFile: aliasPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !alias.isEmpty {
            // The alias might be a version like "20" or "v20.11.0" or "lts/iron"
            // Try to find a matching installed version
            if let match = findInstalledVersion(matching: alias, in: nvmDir) {
                let binPath = (match as NSString).appendingPathComponent("bin")
                if fm.fileExists(atPath: binPath) {
                    return binPath
                }
            }
        }

        // Fallback: pick the latest installed version directory
        guard let versions = try? fm.contentsOfDirectory(atPath: nvmDir) else { return nil }
        let sorted = versions
            .filter { $0.hasPrefix("v") }
            .sorted { compareVersions($0, $1) }

        if let latest = sorted.last {
            let binPath = (nvmDir as NSString)
                .appendingPathComponent(latest)
                .appending("/bin")
            if fm.fileExists(atPath: binPath) {
                return binPath
            }
        }

        return nil
    }

    /// Find an installed node version matching a partial alias like "20" or "v20.11.0".
    private static func findInstalledVersion(matching alias: String, in nvmDir: String) -> String? {
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: nvmDir) else { return nil }

        // Normalize: strip leading "v" if present
        let normalized = alias.hasPrefix("v") ? String(alias.dropFirst()) : alias

        // Try exact match first
        let exact = "v\(normalized)"
        if versions.contains(exact) {
            return (nvmDir as NSString).appendingPathComponent(exact)
        }

        // Partial match: alias "20" should match "v20.x.y"
        let matching = versions
            .filter { $0.hasPrefix("v") }
            .filter {
                let ver = String($0.dropFirst()) // strip "v"
                return ver.hasPrefix(normalized + ".") || ver == normalized
            }
            .sorted { compareVersions($0, $1) }

        if let best = matching.last {
            return (nvmDir as NSString).appendingPathComponent(best)
        }

        return nil
    }

    /// Simple semver-like comparison for version strings like "v20.11.0".
    private static func compareVersions(_ a: String, _ b: String) -> Bool {
        let aParts = a.dropFirst().split(separator: ".").compactMap { Int($0) }
        let bParts = b.dropFirst().split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av < bv }
        }
        return false
    }
}
