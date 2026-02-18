import Foundation

/// Detects the OpenAI Codex CLI binary so that `OpenAICodexAdapter`
/// can invoke `codex exec` even when the app is launched outside
/// a shell environment (e.g. from Finder / Dock).
enum CodexPathDetector {
    /// Common locations where the `codex` binary may be installed.
    private static let knownPaths: [String] = [
        "/opt/homebrew/bin",          // Homebrew on Apple Silicon
        "/usr/local/bin",             // Homebrew on Intel / manual installs
        "/opt/homebrew/Caskroom",     // Homebrew cask
    ]

    /// Returns the full path to the `codex` binary, or `nil` if not found.
    static func detectCodexPath() -> String? {
        let fm = FileManager.default

        // 1. Check well-known Homebrew / system paths
        for dir in knownPaths {
            let candidate = (dir as NSString).appendingPathComponent("codex")
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // 2. Check nvm-managed Node.js global bins (npm install -g @openai/codex)
        if let nvmBin = NvmPathDetector.detectNvmPath() {
            let candidate = (nvmBin as NSString).appendingPathComponent("codex")
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // 3. Fallback: use `which` to search the user's PATH
        return whichCodex()
    }

    /// Returns additional PATH entries that should be prepended when
    /// launching the `codex` subprocess so it can find Node.js and itself.
    static func additionalPaths() -> [String] {
        var paths: [String] = []

        // Add nvm bin path if present
        if let nvmPath = NvmPathDetector.detectNvmPath() {
            paths.append(nvmPath)
        }

        // Add common Homebrew paths
        paths.append("/opt/homebrew/bin")
        paths.append("/usr/local/bin")

        return paths
    }

    /// Runs `/usr/bin/which codex` as a fallback path detection method.
    private static func whichCodex() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]

        // Provide a reasonable PATH for the subprocess
        var env = ProcessInfo.processInfo.environment
        let extra = additionalPaths().joined(separator: ":")
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(extra):\(existing)"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }
}
