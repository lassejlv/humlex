import ClaudeCodeSDK
import Combine
import Foundation

// MARK: - Claude Code Adapter

struct ClaudeCodeAdapter: LLMProviderAdapter {
    let provider: AIProvider = .claudeCode

    /// The working directory for Claude Code operations.
    var workingDirectory: String?

    /// Optional session ID for conversation continuity.
    var sessionID: String?

    func fetchModels(apiKey: String) async throws -> [LLMModel] {
        // Verify the Claude CLI is installed by attempting to create a client
        let config = makeConfiguration()
        do {
            let client = try ClaudeCodeClient(configuration: config)
            let isValid = try await client.validateCommand("claude")
            guard isValid else {
                throw AdapterError.api(
                    message:
                        "Claude Code CLI not found. Install with: npm install -g @anthropic/claude-code"
                )
            }
        } catch let error as ClaudeCodeError {
            throw AdapterError.api(message: error.localizedDescription)
        }

        // Return a fixed model list — Claude Code manages its own model selection
        return [
            LLMModel(provider: .claudeCode, modelID: "claude-code", displayName: "Claude Code")
        ]
    }

    func streamMessage(
        history: [LLMChatMessage],
        modelID: String,
        apiKey: String,
        tools: [MCPTool],
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        let config = makeConfiguration()
        let client: ClaudeCodeClient
        do {
            client = try ClaudeCodeClient(configuration: config)
        } catch {
            throw AdapterError.api(
                message: "Failed to initialize Claude Code: \(error.localizedDescription)")
        }

        // Build the prompt from the most recent user message
        let prompt = buildPrompt(from: history)

        // Build options
        var options = ClaudeCodeOptions()
        options.permissionMode = .acceptEdits

        // Extract system prompt if present
        if let systemContent = history.first(where: { $0.role == .system })?.content,
            !systemContent.isEmpty
        {
            options.systemPrompt = systemContent
        }

        // If we have a session ID, resume the conversation
        let result: ClaudeCodeResult
        do {
            if let sessionID {
                result = try await client.resumeConversation(
                    sessionId: sessionID,
                    prompt: prompt,
                    outputFormat: .streamJson,
                    options: options
                )
            } else {
                result = try await client.runSinglePrompt(
                    prompt: prompt,
                    outputFormat: .streamJson,
                    options: options
                )
            }
        } catch let error as ClaudeCodeError {
            throw AdapterError.api(message: error.localizedDescription)
        }

        // Process the result based on its type
        switch result {
        case .stream(let publisher):
            return try await processStream(publisher: publisher, onEvent: onEvent)

        case .text(let content):
            if !content.isEmpty {
                await onEvent(.textDelta(content))
            }
            await onEvent(.done)
            return StreamResult(text: content, toolCalls: [])

        case .json(let resultMessage):
            let text = resultMessage.result ?? ""
            if !text.isEmpty {
                await onEvent(.textDelta(text))
            }
            await onEvent(.done)
            return StreamResult(text: text, toolCalls: [])
        }
    }

    // MARK: - Private Helpers

    private func makeConfiguration() -> ClaudeCodeConfiguration {
        var config = ClaudeCodeConfiguration.default
        config.workingDirectory = workingDirectory
        // Auto-detect nvm paths for robustness
        if let nvmPath = NvmPathDetector.detectNvmPath() {
            config.additionalPaths.append(nvmPath)
        }
        return config
    }

    /// Build a prompt string from the conversation history.
    /// Claude Code expects a single prompt string, not a structured message array.
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

    /// Process a Combine stream publisher into StreamEvents.
    /// Bridges from Combine's AnyPublisher to the async onEvent callback.
    private func processStream(
        publisher: AnyPublisher<ResponseChunk, Error>,
        onEvent: @escaping @Sendable (StreamEvent) async -> Void
    ) async throws -> StreamResult {
        var fullText = ""

        // Bridge Combine publisher to async/await using AsyncStream
        let stream = AsyncThrowingStream<ResponseChunk, Error> { continuation in
            let cancellable = publisher.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        continuation.finish()
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                },
                receiveValue: { chunk in
                    continuation.yield(chunk)
                }
            )
            // Hold the cancellable alive until the stream finishes
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }

        for try await chunk in stream {
            try Task.checkCancellation()

            switch chunk {
            case .assistant(let assistantMessage):
                // Extract text content from the assistant's MessageResponse
                let text = extractText(from: assistantMessage)
                if !text.isEmpty {
                    fullText += text
                    await onEvent(.textDelta(text))
                }

            case .result(let resultMessage):
                // The result message may contain final text
                if let resultText = resultMessage.result, !resultText.isEmpty {
                    // Only emit if we haven't already emitted this text via assistant chunks
                    if fullText.isEmpty {
                        fullText = resultText
                        await onEvent(.textDelta(resultText))
                    }
                }

            case .initSystem, .user:
                // Skip system init and echoed user messages
                break
            }
        }

        if fullText.isEmpty {
            throw AdapterError.missingResponseText
        }

        await onEvent(.done)
        // Claude Code handles tools internally — no tool calls exposed to the app
        return StreamResult(text: fullText, toolCalls: [])
    }

    /// Extract text content from an AssistantMessage's MessageResponse.
    private func extractText(from assistantMessage: AssistantMessage) -> String {
        var text = ""
        for content in assistantMessage.message.content {
            switch content {
            case .text(let t, _):
                text += t
            case .thinking:
                // Skip thinking blocks — they're internal reasoning
                break
            default:
                // Skip tool_use, server_tool_use, etc. — handled internally by Claude Code
                break
            }
        }
        return text
    }
}

// MARK: - Claude Code Availability Check

enum ClaudeCodeAvailability {
    case available
    case notInstalled
    case error(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var statusMessage: String {
        switch self {
        case .available:
            return "Claude Code CLI is installed and available"
        case .notInstalled:
            return "Claude Code CLI not found. Install with: npm install -g @anthropic/claude-code"
        case .error(let message):
            return "Error checking Claude Code: \(message)"
        }
    }

    static func check() async -> ClaudeCodeAvailability {
        do {
            let config = ClaudeCodeConfiguration.default
            let client = try ClaudeCodeClient(configuration: config)
            let isValid = try await client.validateCommand("claude")
            return isValid ? .available : .notInstalled
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
