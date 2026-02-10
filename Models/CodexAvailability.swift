import Foundation

/// Represents the availability and authentication status of the OpenAI Codex CLI.
enum CodexAvailability {
    case available(loggedIn: Bool)
    case notInstalled
    case error(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var isLoggedIn: Bool {
        if case .available(let loggedIn) = self { return loggedIn }
        return false
    }

    var statusMessage: String {
        switch self {
        case .available(let loggedIn):
            if loggedIn {
                return "Codex CLI is installed and authenticated"
            }
            return "Codex CLI is installed but not logged in"
        case .notInstalled:
            return "Codex CLI not found. Install with: npm install -g @openai/codex"
        case .error(let message):
            return "Error checking Codex: \(message)"
        }
    }

    /// Checks whether the Codex CLI is installed and authenticated.
    static func check() async -> CodexAvailability {
        // 1. Find the binary
        guard let codexPath = CodexPathDetector.detectCodexPath() else {
            return .notInstalled
        }

        // 2. Verify the binary actually works: `codex --version`
        let versionOk = await runProcess(
            executablePath: codexPath,
            arguments: ["--version"]
        )
        guard versionOk else {
            return .notInstalled
        }

        // 3. Check login status: `codex login status` (exit 0 = logged in)
        let loggedIn = await runProcess(
            executablePath: codexPath,
            arguments: ["login", "status"]
        )

        return .available(loggedIn: loggedIn)
    }

    /// Runs the `codex login` command which opens a browser for ChatGPT OAuth.
    /// Returns `true` if the login process completed successfully.
    static func performLogin() async -> Bool {
        guard let codexPath = CodexPathDetector.detectCodexPath() else {
            return false
        }

        return await runProcess(
            executablePath: codexPath,
            arguments: ["login"],
            timeout: 120  // Give the user 2 minutes to complete browser login
        )
    }

    // MARK: - Private

    /// Run a process and return whether it exited with status 0.
    private static func runProcess(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 15
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments

                // Set up PATH so Codex can find Node.js and other dependencies
                var env = ProcessInfo.processInfo.environment
                let extra = CodexPathDetector.additionalPaths().joined(separator: ":")
                let existing = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = "\(extra):\(existing)"
                process.environment = env

                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }

                // Set up a timeout
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()

                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }
}
