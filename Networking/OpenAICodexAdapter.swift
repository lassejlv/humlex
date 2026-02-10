import Foundation

// MARK: - OpenAI Codex Adapter

/// Adapter that integrates OpenAI Codex CLI as a provider in Humlex.
/// Uses `codex exec --json` in non-interactive mode to stream JSONL events.
/// Authentication is handled by the Codex CLI itself (ChatGPT OAuth or API key).
struct OpenAICodexAdapter: LLMProviderAdapter {
    let provider: AIProvider = .openAICodex

    /// The working directory for Codex operations.
    var workingDirectory: String?

    /// Sandbox policy for command execution.
    var sandboxMode: CodexSandboxMode = .readOnly

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

        var args = ["exec", "--json", "--sandbox", sandboxMode.rawValue, "--skip-git-repo-check"]

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
    /// Reads stdout incrementally (line-by-line as data arrives) so that both text
    /// and tool-use events are emitted in real-time for live UI updates.
    ///
    /// Event types we handle:
    /// - `item.completed` / `item.started` with `item.type == "agent_message"` — emit textDelta
    /// - `item.completed` with tool item types — emit cliToolUse immediately
    /// - `turn.completed` — mark done
    /// - `error` / `turn.failed` — throw
    private func parseJSONLStream(
        pipe: Pipe,
        process: Process,
        stderrPipe: Pipe,
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        var fullText = ""
        var emittedAny = false
        var collectedToolCalls: [ToolCallInfo] = []
        var toolCallCounter = 0

        let fileHandle = pipe.fileHandleForReading

        // Stream stdout incrementally: read chunks as they arrive and split into lines.
        // This ensures events are emitted to the UI in real-time.
        let lineStream = AsyncStream<String> { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = ""
                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty {
                        // EOF — process has finished writing
                        // Yield any remaining partial line
                        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            continuation.yield(trimmed)
                        }
                        break
                    }
                    if let chunk = String(data: data, encoding: .utf8) {
                        buffer += chunk
                        // Split buffer into complete lines
                        while let newlineRange = buffer.range(of: "\n") {
                            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            buffer = String(buffer[newlineRange.upperBound...])
                            if !line.isEmpty {
                                continuation.yield(line)
                            }
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
            case "item.completed", "item.started":
                guard let item = json["item"] as? [String: Any],
                    let itemType = item["type"] as? String
                else { continue }

                switch itemType {
                case "agent_message":
                    if let text = item["text"] as? String, !text.isEmpty {
                        fullText += text
                        emittedAny = true
                        await onEvent(.textDelta(text))
                    }

                case "command_execution":
                    toolCallCounter += 1
                    let command = item["command"] as? String ?? ""
                    let status = item["status"] as? String ?? ""
                    let id = "codex-tool-\(toolCallCounter)"
                    let argsDict: [String: Any] = ["command": command, "status": status]
                    let argsJSON = Self.jsonString(from: argsDict)
                    emittedAny = true
                    collectedToolCalls.append(ToolCallInfo(id: id, name: "run_command", arguments: argsJSON, serverName: "Codex"))
                    await onEvent(.cliToolUse(id: id, name: "run_command", arguments: argsJSON, serverName: "Codex"))

                case "file_read", "file_read_range":
                    toolCallCounter += 1
                    let filePath = item["file_path"] as? String ?? item["path"] as? String ?? ""
                    let id = "codex-tool-\(toolCallCounter)"
                    let argsJSON = Self.jsonString(from: ["path": filePath])
                    emittedAny = true
                    collectedToolCalls.append(ToolCallInfo(id: id, name: "read_file", arguments: argsJSON, serverName: "Codex"))
                    await onEvent(.cliToolUse(id: id, name: "read_file", arguments: argsJSON, serverName: "Codex"))

                case "file_write", "file_create", "file_edit":
                    toolCallCounter += 1
                    let filePath = item["file_path"] as? String ?? item["path"] as? String ?? ""
                    let toolName = itemType == "file_edit" ? "edit_file" : "write_file"
                    let id = "codex-tool-\(toolCallCounter)"
                    let argsJSON = Self.jsonString(from: ["path": filePath])
                    emittedAny = true
                    collectedToolCalls.append(ToolCallInfo(id: id, name: toolName, arguments: argsJSON, serverName: "Codex"))
                    await onEvent(.cliToolUse(id: id, name: toolName, arguments: argsJSON, serverName: "Codex"))

                case "directory_list", "list_directory":
                    toolCallCounter += 1
                    let dirPath = item["path"] as? String ?? item["directory"] as? String ?? "."
                    let id = "codex-tool-\(toolCallCounter)"
                    let argsJSON = Self.jsonString(from: ["path": dirPath])
                    emittedAny = true
                    collectedToolCalls.append(ToolCallInfo(id: id, name: "list_directory", arguments: argsJSON, serverName: "Codex"))
                    await onEvent(.cliToolUse(id: id, name: "list_directory", arguments: argsJSON, serverName: "Codex"))

                case "mcp_tool_call":
                    toolCallCounter += 1
                    let toolName = item["name"] as? String ?? item["tool_name"] as? String ?? "mcp_tool"
                    let input = item["input"] as? [String: Any] ?? item["arguments"] as? [String: Any] ?? [:]
                    let id = "codex-tool-\(toolCallCounter)"
                    let argsJSON = Self.jsonString(from: input)
                    let serverName = item["server_name"] as? String ?? "Codex"
                    emittedAny = true
                    collectedToolCalls.append(ToolCallInfo(id: id, name: toolName, arguments: argsJSON, serverName: serverName))
                    await onEvent(.cliToolUse(id: id, name: toolName, arguments: argsJSON, serverName: serverName))

                case "reasoning":
                    // Skip reasoning items — these are internal model reasoning, not tool calls
                    break

                default:
                    // Other item types — only surface if they have meaningful data
                    // Skip purely internal items like plan_update, etc.
                    break
                }

            case "turn.completed":
                break

            case "turn.failed":
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
                break

            default:
                break
            }
        }

        // Wait for the process to finish
        process.waitUntilExit()

        // Check if the process exited with an error
        if process.terminationStatus != 0 && !emittedAny {
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
        return StreamResult(text: fullText, toolCalls: collectedToolCalls)
    }

    /// Serialize a dictionary to a JSON string for tool call arguments.
    private static func jsonString(from dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }
}
