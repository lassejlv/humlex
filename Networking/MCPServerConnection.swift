import Foundation

/// Thread-safe store for pending JSON-RPC continuations.
/// Used to decouple the blocking stdio read thread from the actor.
private final class PendingRequestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]

    func store(id: Int, continuation: CheckedContinuation<JSONRPCResponse, Error>) {
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
    }

    func resume(id: Int, with response: JSONRPCResponse) {
        lock.lock()
        let cont = continuations.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(returning: response)
    }

    func remove(id: Int) -> CheckedContinuation<JSONRPCResponse, Error>? {
        lock.lock()
        let cont = continuations.removeValue(forKey: id)
        lock.unlock()
        return cont
    }

    func cancelAll(with error: Error) {
        lock.lock()
        let all = continuations
        continuations.removeAll()
        lock.unlock()
        for (_, cont) in all {
            cont.resume(throwing: error)
        }
    }
}

/// Manages a single MCP server connection over stdio transport.
/// Spawns the server as a subprocess, performs the initialization handshake,
/// discovers tools, and executes tool calls.
actor MCPServerConnection {
    let config: MCPServerConfig
    let serverName: String

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var nextRequestID: Int = 1
    private let pendingRequests = PendingRequestStore()
    private var readThread: Thread?

    private(set) var tools: [MCPTool] = []
    private(set) var serverInfo: MCPServerInfo?
    private(set) var isConnected: Bool = false

    enum ConnectionError: LocalizedError {
        case processNotRunning
        case initializationFailed(String)
        case toolCallFailed(String)
        case timeout
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .processNotRunning:
                return "MCP server process is not running."
            case .initializationFailed(let msg):
                return "MCP initialization failed: \(msg)"
            case .toolCallFailed(let msg):
                return "MCP tool call failed: \(msg)"
            case .timeout:
                return "MCP request timed out."
            case .invalidResponse:
                return "MCP server returned an invalid response."
            }
        }
    }

    init(name: String, config: MCPServerConfig) {
        self.serverName = name
        var cfg = config
        cfg.name = name
        self.config = cfg
    }

    // MARK: - Lifecycle

    /// Start the server process and perform initialization handshake.
    func connect() async throws {
        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        let resolved = resolveExecutable(config.command)
        proc.executableURL = resolved
        // When falling back to /usr/bin/env, prepend the command name
        if resolved.path == "/usr/bin/env" {
            proc.arguments = [config.command] + (config.args ?? [])
        } else {
            proc.arguments = config.args ?? []
        }
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        // Inherit current environment and merge server-specific env vars
        var environment = ProcessInfo.processInfo.environment
        if let env = config.env {
            for (key, value) in env {
                environment[key] = value
            }
        }
        // Ensure common tool paths are available
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin"
        // Resolve globs for nvm paths
        let resolvedExtras = extraPaths.flatMap { pattern -> [String] in
            if pattern.contains("*") {
                let glob = Foundation.glob_t()
                var g = glob
                Foundation.glob(pattern, 0, nil, &g)
                defer { globfree(&g) }
                return (0..<Int(g.gl_pathc)).compactMap { i in
                    g.gl_pathv[i].flatMap { String(cString: $0) }
                }
            }
            return [pattern]
        }
        environment["PATH"] = (resolvedExtras + [currentPath]).joined(separator: ":")
        proc.environment = environment

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        try proc.run()

        // Start reading stdout on a background thread (NOT on the actor)
        // so that blocking reads don't deadlock the actor.
        let store = self.pendingRequests
        let handle = stdout.fileHandleForReading
        let thread = Thread {
            Self.readLoop(handle: handle, store: store)
        }
        thread.name = "MCP-read-\(serverName)"
        thread.qualityOfService = .userInitiated
        thread.start()
        self.readThread = thread

        // Perform MCP initialization handshake
        try await initialize()
        isConnected = true

        // Discover tools
        try await discoverTools()
    }

    /// Disconnect and terminate the server process.
    func disconnect() {
        readThread?.cancel()
        readThread = nil

        stdinPipe?.fileHandleForWriting.closeFile()
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isConnected = false
        tools = []

        // Cancel any pending requests
        pendingRequests.cancelAll(with: ConnectionError.processNotRunning)
    }

    // MARK: - Tool Operations

    /// Call an MCP tool and return the result content.
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
        let args: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "arguments": AnyCodable(arguments),
        ]

        let response = try await sendRequest(method: "tools/call", params: args)

        guard let result = response.result else {
            if let error = response.error {
                throw ConnectionError.toolCallFailed(error.message)
            }
            throw ConnectionError.invalidResponse
        }

        // Decode the result into MCPToolCallResult
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(MCPToolCallResult.self, from: data)
    }

    // MARK: - Private: Initialization

    private func initialize() async throws {
        let params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable("2024-11-05"),
            "capabilities": AnyCodable([String: Any]()),
            "clientInfo": AnyCodable([
                "name": "Humlex",
                "version": "1.0.0",
            ] as [String: Any]),
        ]

        let response = try await sendRequest(method: "initialize", params: params)

        if let error = response.error {
            throw ConnectionError.initializationFailed(error.message)
        }

        // Decode server info
        if let result = response.result {
            let data = try JSONEncoder().encode(result)
            let initResult = try JSONDecoder().decode(MCPInitializeResult.self, from: data)
            serverInfo = initResult.serverInfo
        }

        // Send initialized notification
        sendNotification(method: "notifications/initialized", params: nil)
    }

    private func discoverTools() async throws {
        var allTools: [MCPTool] = []
        var cursor: String? = nil

        repeat {
            var params: [String: AnyCodable] = [:]
            if let cursor {
                params["cursor"] = AnyCodable(cursor)
            }

            let response = try await sendRequest(
                method: "tools/list",
                params: params.isEmpty ? nil : params
            )

            if response.error != nil {
                // Server might not support tools — that's OK
                break
            }

            guard let result = response.result else { break }

            let data = try JSONEncoder().encode(result)
            let toolList = try JSONDecoder().decode(MCPToolListResult.self, from: data)

            for def in toolList.tools {
                let schema: [String: AnyCodable]
                if let s = def.inputSchema,
                   let dict = s.value as? [String: Any] {
                    schema = dict.mapValues { AnyCodable($0) }
                } else {
                    schema = ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())]
                }

                allTools.append(MCPTool(
                    serverName: serverName,
                    name: def.name,
                    description: def.description ?? "",
                    inputSchema: schema
                ))
            }

            cursor = toolList.nextCursor
        } while cursor != nil

        tools = allTools
    }

    // MARK: - Private: JSON-RPC Transport

    private func sendRequest(
        method: String,
        params: [String: AnyCodable]?
    ) async throws -> JSONRPCResponse {
        guard let process, process.isRunning else {
            throw ConnectionError.processNotRunning
        }

        let id = nextRequestID
        nextRequestID += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        guard var line = String(data: data, encoding: .utf8) else {
            throw ConnectionError.invalidResponse
        }
        line += "\n"

        stdinPipe?.fileHandleForWriting.write(line.data(using: .utf8)!)

        let store = self.pendingRequests

        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            store.store(id: id, continuation: continuation)

            // 30-second timeout
            Task.detached {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = store.remove(id: id) {
                    cont.resume(throwing: ConnectionError.timeout)
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: AnyCodable]?) {
        guard let process, process.isRunning else { return }

        let notification = JSONRPCNotification(method: method, params: params)
        guard let data = try? JSONEncoder().encode(notification),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line += "\n"
        stdinPipe?.fileHandleForWriting.write(line.data(using: .utf8)!)
    }

    /// Blocking read loop that runs on a dedicated background thread.
    /// Reads newline-delimited JSON-RPC responses from stdout and dispatches them
    /// via the thread-safe PendingRequestStore.
    private static func readLoop(handle: FileHandle, store: PendingRequestStore) {
        var buffer = Data()

        while !Thread.current.isCancelled {
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF — process exited
                break
            }

            buffer.append(chunk)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                guard !lineData.isEmpty else { continue }

                // Try to decode as JSON-RPC response
                if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: Data(lineData)),
                   let id = response.id {
                    store.resume(id: id, with: response)
                }
                // If no id, it's a notification from server — ignore for now
            }
        }
    }

    // MARK: - Helpers

    private func resolveExecutable(_ command: String) -> URL {
        // If it's an absolute path, use directly
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }

        // For commands like "node", "python", "npx", resolve via PATH
        // Try common locations first
        let searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.nvm/versions/node", // will need glob
            "\(NSHomeDirectory())/.local/bin",
        ]

        for dir in searchPaths {
            let fullPath = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }

        // Fallback: try /usr/bin/env to resolve it
        return URL(fileURLWithPath: "/usr/bin/env")
    }
}
