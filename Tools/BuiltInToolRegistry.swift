//
//  BuiltInToolRegistry.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import Foundation

/// Central registry for all built-in tools.
/// Provides tool discovery, schema generation, and execution routing.
final class BuiltInToolRegistry {
    static let shared = BuiltInToolRegistry()
    
    /// Sentinel server name used to identify built-in tools vs MCP tools.
    static let builtInServerName = "__builtin__"
    
    /// Check if a tool call is a built-in tool (vs an MCP tool).
    static func isBuiltIn(serverName: String) -> Bool {
        serverName == builtInServerName
    }
    
    private var tools: [String: BuiltInTool] = [:]
    private let executionLock = NSLock()
    
    private init() {
        registerDefaultTools()
    }
    
    // MARK: - Registration
    
    /// Register a new built-in tool.
    /// - Parameter tool: The tool to register
    /// - Throws: If a tool with the same name is already registered
    func register(_ tool: BuiltInTool) {
        let name = tool.name
        if tools[name] != nil {
            print("[BuiltInToolRegistry] Warning: Tool '\(name)' is being re-registered")
        }
        tools[name] = tool
        print("[BuiltInToolRegistry] Registered tool: \(name)")
    }
    
    /// Unregister a tool by name.
    /// - Parameter name: The tool name to unregister
    func unregister(name: String) {
        tools.removeValue(forKey: name)
        print("[BuiltInToolRegistry] Unregistered tool: \(name)")
    }
    
    /// Register multiple tools at once.
    /// - Parameter tools: Array of tools to register
    func register(_ tools: [BuiltInTool]) {
        for tool in tools {
            register(tool)
        }
    }
    
    // MARK: - Discovery
    
    /// Get all registered tools as MCPTool definitions for AI models.
    /// - Returns: Array of MCPTool objects representing all built-in tools
    func definitions() -> [MCPTool] {
        return tools.values.map { tool in
            MCPTool(
                serverName: Self.builtInServerName,
                name: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema
            )
        }
    }
    
    /// Get metadata for all registered tools.
    /// - Returns: Array of tool metadata for display/documentation
    func metadata() -> [BuiltInToolMetadata] {
        return tools.values.map { tool in
            BuiltInToolMetadata(
                name: tool.name,
                description: tool.description,
                isDestructive: tool.isDestructive,
                parameterSummary: extractParameterSummary(from: tool.inputSchema)
            )
        }.sorted { $0.name < $1.name }
    }
    
    /// Check if a tool is registered.
    /// - Parameter name: The tool name to check
    /// - Returns: True if the tool exists
    func hasTool(named name: String) -> Bool {
        return tools[name] != nil
    }
    
    /// Check if a tool is destructive.
    /// - Parameter name: The tool name to check
    /// - Returns: True if the tool is destructive, false if not or if tool doesn't exist
    func isDestructive(named name: String) -> Bool {
        return tools[name]?.isDestructive ?? false
    }
    
    // MARK: - Execution
    
    /// Execute a tool by name with the given arguments.
    /// - Parameters:
    ///   - name: The tool name to execute
    ///   - arguments: Dictionary of argument names to values
    ///   - workingDirectory: The working directory for sandboxed operations
    /// - Returns: The tool's output as a string
    /// - Throws: ToolExecutionError if tool not found or execution fails
    func execute(
        toolName name: String,
        arguments: [String: Any],
        workingDirectory: String
    ) async throws -> String {
        guard let tool = tools[name] else {
            throw ToolExecutionError.toolNotFound(name)
        }
        
        do {
            return try await tool.execute(arguments: arguments, workingDirectory: workingDirectory)
        } catch {
            throw ToolExecutionError.executionFailed(name, error.localizedDescription)
        }
    }
    
    /// Get a list of all registered tool names.
    var registeredToolNames: [String] {
        return Array(tools.keys).sorted()
    }
    
    /// Get the count of registered tools.
    var toolCount: Int {
        return tools.count
    }
    
    // MARK: - Private
    
    private func registerDefaultTools() {
        // File system tools
        register(ReadFileTool())
        register(WriteFileTool())
        register(EditFileTool())
        register(ListDirectoryTool())
        register(SearchFilesTool())
        register(RunCommandTool())
        
        // HTTP/Web tools
        register(FetchTool())
        
        print("[BuiltInToolRegistry] Registered \(tools.count) default tools")
    }
    
    private func extractParameterSummary(from schema: [String: AnyCodable]) -> String {
        guard let properties = schema["properties"]?.value as? [String: Any] else {
            return ""
        }
        let required = (schema["required"]?.value as? [String]) ?? []
        
        let params = properties.keys.map { key -> String in
            let isRequired = required.contains(key)
            return isRequired ? key : "\(key)?"
        }.sorted()
        
        return params.joined(separator: ", ")
    }
}

// MARK: - Errors

enum ToolExecutionError: LocalizedError {
    case toolNotFound(String)
    case executionFailed(String, String)
    case invalidArguments(String, String)
    
    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool '\(name)' not found in registry"
        case .executionFailed(let name, let reason):
            return "Tool '\(name)' execution failed: \(reason)"
        case .invalidArguments(let name, let reason):
            return "Tool '\(name)' received invalid arguments: \(reason)"
        }
    }
}
