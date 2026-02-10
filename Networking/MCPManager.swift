import Foundation

/// Manages all MCP server connections, exposes aggregated tools, and routes tool calls.
@MainActor
final class MCPManager: ObservableObject {
    static let shared = MCPManager()

    /// Status of an individual MCP server connection.
    enum ServerStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    @Published private(set) var tools: [MCPTool] = []
    @Published private(set) var serverStatuses: [String: ServerStatus] = [:]
    @Published private(set) var isLoading = false

    private var connections: [String: MCPServerConnection] = [:]

    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Humlex")
        return appDir.appendingPathComponent("mcp.json")
    }

    private init() {}

    // MARK: - Public API

    /// Load config from disk and connect to all configured servers.
    func loadAndConnect() async {
        isLoading = true
        defer { isLoading = false }

        // Disconnect existing connections
        await disconnectAll()

        // Load config
        guard let configs = loadConfig() else { return }

        // Connect to each server concurrently
        await withTaskGroup(of: Void.self) { group in
            for (name, config) in configs {
                serverStatuses[name] = .connecting
                group.addTask { [weak self] in
                    await self?.connectServer(name: name, config: config)
                }
            }
        }

        aggregateTools()
    }

    /// Reconnect a single server by name.
    func reconnect(serverName: String) async {
        // Disconnect existing
        if let conn = connections[serverName] {
            await conn.disconnect()
            connections[serverName] = nil
        }

        // Reload config to get current settings
        guard let configs = loadConfig(),
              let config = configs[serverName] else {
            serverStatuses[serverName] = .error("Server not found in config")
            return
        }

        serverStatuses[serverName] = .connecting
        await connectServer(name: serverName, config: config)
        aggregateTools()
    }

    /// Disconnect all servers.
    func disconnectAll() async {
        for (_, conn) in connections {
            await conn.disconnect()
        }
        connections.removeAll()
        serverStatuses.removeAll()
        tools = []
    }

    /// Call a tool on the appropriate server.
    func callTool(serverName: String, toolName: String, arguments: [String: Any]) async throws -> MCPToolCallResult {
        guard let conn = connections[serverName] else {
            throw MCPManagerError.serverNotConnected(serverName)
        }
        return try await conn.callTool(name: toolName, arguments: arguments)
    }

    /// Find which server owns a tool by its full ID (serverName::toolName).
    func serverForTool(toolID: String) -> String? {
        let parts = toolID.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        // "server::tool" splits as ["server", "", "tool"]
        return String(parts[0])
    }

    /// Add a new server to the config file and connect to it.
    func addServer(name: String, command: String, args: [String], env: [String: String]?) async {
        // Load existing config or start fresh
        var servers = loadConfig() ?? [:]

        var config = MCPServerConfig(command: command, args: args.isEmpty ? nil : args, env: env)
        config.name = name
        servers[name] = config

        saveConfig(servers)

        // Connect the new server
        serverStatuses[name] = .connecting
        await connectServer(name: name, config: config)
        aggregateTools()
    }

    /// Remove a server from config and disconnect it.
    func removeServer(name: String) async {
        // Disconnect
        if let conn = connections[name] {
            await conn.disconnect()
            connections[name] = nil
        }
        serverStatuses[name] = nil

        // Remove from config
        var servers = loadConfig() ?? [:]
        servers.removeValue(forKey: name)
        saveConfig(servers)

        aggregateTools()
    }

    // MARK: - Private

    private func loadConfig() -> [String: MCPServerConfig]? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: configURL)
            let configFile = try JSONDecoder().decode(MCPConfigFile.self, from: data)
            // Set the name field on each config from the dictionary key
            var result: [String: MCPServerConfig] = [:]
            for (name, var config) in configFile.mcpServers {
                config.name = name
                result[name] = config
            }
            return result
        } catch {
            print("[MCPManager] Failed to load config: \(error)")
            return nil
        }
    }

    private func saveConfig(_ servers: [String: MCPServerConfig]) {
        let configFile = MCPConfigFile(mcpServers: servers)
        do {
            // Ensure directory exists
            let dir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configFile)
            try data.write(to: configURL)
        } catch {
            print("[MCPManager] Failed to save config: \(error)")
        }
    }

    private func connectServer(name: String, config: MCPServerConfig) async {
        let connection = MCPServerConnection(name: name, config: config)
        do {
            try await connection.connect()
            await MainActor.run {
                connections[name] = connection
                serverStatuses[name] = .connected
            }
        } catch {
            await MainActor.run {
                serverStatuses[name] = .error(error.localizedDescription)
            }
        }
    }

    private func aggregateTools() {
        // Gather tools from all connections asynchronously
        Task {
            var gathered: [MCPTool] = []
            for (_, conn) in connections {
                let serverTools = await conn.tools
                gathered.append(contentsOf: serverTools)
            }
            await MainActor.run {
                self.tools = gathered
            }
        }
    }

    enum MCPManagerError: LocalizedError {
        case serverNotConnected(String)
        case toolNotFound(String)

        var errorDescription: String? {
            switch self {
            case .serverNotConnected(let name):
                return "MCP server '\(name)' is not connected."
            case .toolNotFound(let name):
                return "MCP tool '\(name)' not found."
            }
        }
    }
}
