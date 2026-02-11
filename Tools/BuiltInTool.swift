//
//  BuiltInTool.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import Foundation

/// Protocol for built-in tools that can be registered and executed by the AI.
/// Built-in tools run locally within the app and don't require external MCP servers.
protocol BuiltInTool {
    /// Unique tool name (e.g., "read_file", "fetch")
    var name: String { get }
    
    /// Human-readable description of what the tool does
    var description: String { get }
    
    /// JSON Schema defining the tool's input parameters
    var inputSchema: [String: AnyCodable] { get }
    
    /// Whether this tool makes destructive changes (files, data, etc.)
    /// Destructive tools require user confirmation unless in dangerous mode.
    var isDestructive: Bool { get }
    
    /// Execute the tool with the given arguments.
    /// - Parameters:
    ///   - arguments: Dictionary of argument names to values from the AI
    ///   - workingDirectory: The current working directory for sandboxed file operations
    /// - Returns: String result to send back to the AI
    /// - Throws: Errors are caught and returned as error messages to the AI
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String
}

/// Metadata about a built-in tool for display and documentation purposes.
struct BuiltInToolMetadata {
    let name: String
    let description: String
    let isDestructive: Bool
    let parameterSummary: String
}

// MARK: - Tool Schema Helpers

extension BuiltInTool {
    /// Helper to create a simple object schema with properties.
    static func objectSchema(properties: [String: [String: Any]], required: [String] = []) -> [String: AnyCodable] {
        return [
            "type": AnyCodable("object"),
            "properties": AnyCodable(properties),
            "required": AnyCodable(required)
        ]
    }
    
    /// Helper to create a string property definition.
    static func stringProperty(description: String, enumValues: [String]? = nil) -> [String: Any] {
        var prop: [String: Any] = [
            "type": "string",
            "description": description
        ]
        if let enumValues = enumValues {
            prop["enum"] = enumValues
        }
        return prop
    }
    
    /// Helper to create a number property definition.
    static func numberProperty(description: String, minimum: Double? = nil, maximum: Double? = nil) -> [String: Any] {
        var prop: [String: Any] = [
            "type": "number",
            "description": description
        ]
        if let minimum = minimum {
            prop["minimum"] = minimum
        }
        if let maximum = maximum {
            prop["maximum"] = maximum
        }
        return prop
    }
    
    /// Helper to create an object property definition (for headers, etc.).
    static func objectProperty(description: String) -> [String: Any] {
        return [
            "type": "object",
            "description": description
        ]
    }
    
    /// Helper to create a boolean property definition.
    static func booleanProperty(description: String) -> [String: Any] {
        return [
            "type": "boolean",
            "description": description
        ]
    }
}
