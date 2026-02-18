import Foundation

// MARK: - MCP Configuration

/// Configuration for an MCP server, loaded from mcp.json.
/// Format matches Claude Desktop's config format.
struct MCPServerConfig: Codable, Identifiable {
    let command: String
    let args: [String]?
    let env: [String: String]?

    /// Not decoded from JSON — set programmatically from the dictionary key.
    var name: String = ""
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case command, args, env
    }
}

/// Top-level config file structure.
struct MCPConfigFile: Codable {
    let mcpServers: [String: MCPServerConfig]
}

// MARK: - MCP Tool

/// An MCP tool exposed by a server.
struct MCPTool: Identifiable, Hashable {
    let serverName: String
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]

    var id: String { "\(serverName)::\(name)" }

    static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - JSON-RPC 2.0 Types

struct JSONRPCRequest: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCNotification: Encodable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

// MARK: - MCP-Specific Response Types

struct MCPInitializeResult: Decodable {
    let protocolVersion: String
    let capabilities: MCPCapabilities?
    let serverInfo: MCPServerInfo?
}

struct MCPCapabilities: Decodable {
    let tools: MCPToolCapability?
    let resources: MCPResourceCapability?
    let prompts: MCPPromptCapability?

    struct MCPToolCapability: Decodable {
        let listChanged: Bool?
    }

    struct MCPResourceCapability: Decodable {
        let subscribe: Bool?
        let listChanged: Bool?
    }

    struct MCPPromptCapability: Decodable {
        let listChanged: Bool?
    }
}

struct MCPServerInfo: Decodable {
    let name: String
    let version: String?
}

struct MCPToolListResult: Decodable {
    let tools: [MCPToolDefinition]
    let nextCursor: String?
}

struct MCPToolDefinition: Decodable {
    let name: String
    let description: String?
    let inputSchema: AnyCodable?
}

struct MCPToolCallResult: Decodable {
    let content: [MCPContent]
    let isError: Bool?
}

struct MCPContent: Decodable {
    let type: String
    let text: String?
    let data: String?       // base64 for images
    let mimeType: String?
}

// MARK: - AnyCodable

/// A type-erased Codable value for dynamic JSON structures.
struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type: \(type(of: value))")
            )
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality for hashing — compare JSON representation
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let lData = try? encoder.encode(lhs),
              let rData = try? encoder.encode(rhs) else {
            return false
        }
        return lData == rData
    }

    func hash(into hasher: inout Hasher) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(self) {
            hasher.combine(data)
        }
    }

    /// Convert back to a Swift dictionary
    var asDictionary: [String: Any]? {
        value as? [String: Any]
    }

    /// Convert to JSON Data for embedding in API requests
    var jsonData: Data? {
        try? JSONEncoder().encode(self)
    }
}
