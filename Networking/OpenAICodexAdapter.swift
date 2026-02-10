import Foundation

// MARK: - OpenAI Codex Adapter

/// Adapter that integrates OpenAI Codex CLI as a provider in Humlex.
/// Uses `codex exec --json` in non-interactive mode to stream JSONL events.
/// Authentication is handled by the Codex CLI itself (ChatGPT OAuth or API key).
struct OpenAICodexAdapter: LLMProviderAdapter {
    let provider: AIProvider = .openAICodex

    /// The working directory for Codex operations.
    var workingDirectory: String?

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        // Verify the Codex CLI is installed
        guard let codexPath = CodexPathDetector.detectCodexPath() else {
            throw AdapterError.api(
                message:
                    "OpenAI Codex CLI not found. Install with: npm install -g @openai/codex\nOr: brew install --cask codex"
            )
        }

        // Verify it actually runs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        configureEnvironment(for: process)

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw AdapterError.api(
                    message: "Codex CLI found but failed to run. Try reinstalling.")
            }
        } catch {
            throw AdapterError.api(message: "Failed to verify Codex CLI: \(error.localizedDescription)")
        }

        // Recommended models get reasoning effort variants (low/medium/high).
        // Model IDs use "::" separator to encode effort: "gpt-5.3-codex::high"
        // Alternative/older models are listed with default effort only.
        let recommendedModels: [(id: String, name: String)] = [
            ("gpt-5.3-codex", "GPT-5.3 Codex"),
            ("gpt-5.2-codex", "GPT-5.2 Codex"),
            ("gpt-5.1-codex-mini", "GPT-5.1 Codex Mini"),
        ]
        let effortLevels: [(suffix: String, label: String)] = [
            ("low", "Low"),
            ("medium", "Medium"),
            ("high", "High"),
        ]

        var models: [LLMModel] = []
        for model in recommendedModels {
            for effort in effortLevels {
                models.append(LLMModel(
                    provider: .openAICodex,
                    modelID: "\(model.id)::\(effort.suffix)",
                    displayName: "\(model.name) (\(effort.label))"
                ))
            }
        }

        // Alternative models — single entry each (uses Codex default effort)
        let alternativeModels: [(id: String, name: String)] = [
            ("gpt-5.1-codex-max", "GPT-5.1 Codex Max"),
            ("gpt-5.2", "GPT-5.2"),
            ("gpt-5.1", "GPT-5.1"),
            ("gpt-5.1-codex", "GPT-5.1 Codex"),
            ("gpt-5-codex", "GPT-5 Codex"),
            ("gpt-5-codex-mini", "GPT-5 Codex Mini"),
            ("gpt-5", "GPT-5"),
        ]
        for model in alternativeModels {
            models.append(LLMModel(
                provider: .openAICodex,
                modelID: model.id,
                displayName: model.name
            ))
        }

        return models
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        guard let codexPath = CodexPathDetector.detectCodexPath() else {
            throw AdapterError.api(
                message: "OpenAI Codex CLI not found. Install with: npm install -g @openai/codex")
        }

        // Build the prompt from the most recent user message
        let prompt = buildPrompt(from: history)

        // Construct the codex exec command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)

        var args = ["exec", "--json", "--sandbox", "read-only", "--skip-git-repo-check"]

        // Parse modelID — may contain "::effort" suffix (e.g. "gpt-5.3-codex::high")
        let (baseModel, reasoningEffort) = Self.parseModelID(modelID)

        // Pass the selected model via --model flag
        if !baseModel.isEmpty && baseModel != "codex" {
            args += ["--model", baseModel]
        }

        // Pass reasoning effort if specified
        if let effort = reasoningEffort {
            args += ["-c", "model_reasoning_effort=\"\(effort)\""]
        }

        // Set working directory if available
        if let workDir = workingDirectory, !workDir.isEmpty {
            args += ["--cd", workDir]
        }

        // Add the prompt
        args.append(prompt)
        process.arguments = args
        configureEnvironment(for: process)

        // Set up stdout pipe for JSONL output
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AdapterError.api(
                message: "Failed to launch Codex: \(error.localizedDescription)")
        }

        // Parse JSONL output from stdout
        let result = try await parseJSONLStream(
            pipe: stdoutPipe,
            process: process,
            stderrPipe: stderrPipe,
            onEvent: onEvent
        )

        return result
    }

    // MARK: - Private Helpers

    /// Parse a modelID that may contain a reasoning effort suffix.
    /// Format: "gpt-5.3-codex::high" → ("gpt-5.3-codex", "high")
    /// Plain:  "gpt-5.3-codex"       → ("gpt-5.3-codex", nil)
    private static func parseModelID(_ modelID: String) -> (baseModel: String, effort: String?) {
        let parts = modelID.components(separatedBy: "::")
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (modelID, nil)
    }

    /// Configure the process environment with proper PATH entries.
    private func configureEnvironment(for process: Process) {
        var env = ProcessInfo.processInfo.environment
        let extra = CodexPathDetector.additionalPaths().joined(separator: ":")
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(extra):\(existing)"
        process.environment = env
    }

    /// Build a prompt string from the conversation history.
    /// Codex expects a single prompt string, not a structured message array.
    /// We send the most recent user message as the prompt.
    private func buildPrompt(from history: [LLMChatMessage]) -> String {
        // Find the last user message
        if let lastUserMessage = history.last(where: { $0.role == .user }) {
            return lastUserMessage.content
        }
        // Fallback: concatenate all non-system messages
        return
            history
            .filter { $0.role != .system }
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n\n")
    }

    /// Parse the JSONL stream from `codex exec --json`.
    ///
    /// Event types we handle:
    /// - `thread.started` — log for debugging
    /// - `item.completed` with `item.type == "agent_message"` — emit text
    /// - `turn.completed` — mark done
    /// - `error` — throw
    private func parseJSONLStream(
        pipe: Pipe,
        process: Process,
        stderrPipe: Pipe,
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        var fullText = ""
        var emittedAny = false

        // Read stdout line by line
        let fileHandle = pipe.fileHandleForReading

        // Use an AsyncStream to bridge the file handle reading
        let lineStream = AsyncStream<String> { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = fileHandle.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            continuation.yield(trimmed)
                        }
                    }
                }
                continuation.finish()
            }
        }

        for await line in lineStream {
            try Task.checkCancellation()

            guard let data = line.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            guard let eventType = json["type"] as? String else { continue }

            switch eventType {
            case "item.completed":
                // Extract the item
                guard let item = json["item"] as? [String: Any],
                    let itemType = item["type"] as? String
                else { continue }

                if itemType == "agent_message" {
                    if let text = item["text"] as? String, !text.isEmpty {
                        fullText += text
                        emittedAny = true
                        await onEvent(.textDelta(text))
                    }
                }

            case "item.started":
                // Optionally we could show a "thinking" indicator here
                // For now, we extract partial text from in-progress agent messages
                if let item = json["item"] as? [String: Any],
                    let itemType = item["type"] as? String,
                    itemType == "agent_message",
                    let text = item["text"] as? String, !text.isEmpty {
                    fullText += text
                    emittedAny = true
                    await onEvent(.textDelta(text))
                }

            case "turn.completed":
                // Turn finished — we're done
                break

            case "turn.failed":
                // Extract error message if available
                let errorMsg =
                    (json["error"] as? [String: Any])?["message"] as? String
                    ?? "Codex turn failed"
                throw AdapterError.api(message: errorMsg)

            case "error":
                let errorMsg =
                    json["message"] as? String
                    ?? json["error"] as? String
                    ?? "Unknown Codex error"
                throw AdapterError.api(message: errorMsg)

            case "thread.started", "turn.started":
                // Informational events — skip
                break

            default:
                // Unknown event types — skip gracefully
                break
            }
        }

        // Wait for the process to finish
        process.waitUntilExit()

        // Check if the process exited with an error
        if process.terminationStatus != 0 && !emittedAny {
            // Try to get stderr for error context
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let errorMessage =
                stderrText.isEmpty
                ? "Codex exited with status \(process.terminationStatus)"
                : stderrText

            throw AdapterError.api(message: errorMessage)
        }

        if !emittedAny {
            throw AdapterError.missingResponseText
        }

        await onEvent(.done)
        // Codex handles tools internally — no tool calls exposed to the app
        return StreamResult(text: fullText, toolCalls: [])
    }
}
