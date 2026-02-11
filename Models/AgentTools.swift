//
//  AgentTools.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import Foundation

/// Provides compatibility layer between old AgentTools API and new BuiltInToolRegistry.
/// New code should use BuiltInToolRegistry directly.
enum AgentTools {
    /// Sentinel server name used to identify built-in tools vs MCP tools.
    static let builtInServerName = "__builtin__"
    
    /// Check if a tool call is a built-in agent tool (vs an MCP tool).
    static func isBuiltIn(serverName: String) -> Bool {
        BuiltInToolRegistry.isBuiltIn(serverName: serverName)
    }
    
    /// Check if a built-in tool is destructive and needs user confirmation.
    static func isDestructive(_ toolName: String) -> Bool {
        BuiltInToolRegistry.shared.isDestructive(named: toolName)
    }
    
    /// Generate MCPTool definitions for all built-in tools.
    /// Delegates to BuiltInToolRegistry.
    static func definitions() -> [MCPTool] {
        return BuiltInToolRegistry.shared.definitions()
    }
    
    /// Generate MCPTool definition for fetch tool only.
    /// Used in normal chat mode to enable web fetching without agent mode.
    static func fetchDefinitions() -> [MCPTool] {
        let allTools = BuiltInToolRegistry.shared.definitions()
        return allTools.filter { $0.name == "fetch" }
    }
    
    /// System prompt injected when agent mode is active.
    static func systemPrompt(workingDirectory: String) -> String {
        let metadata = BuiltInToolRegistry.shared.metadata()
        let fileTools = metadata.filter { !["run_command", "fetch"].contains($0.name) }
        let commandTool = metadata.first { $0.name == "run_command" }
        let fetchTool = metadata.first { $0.name == "fetch" }
        
        var toolDescriptions: [String] = []
        
        // File system tools
        for tool in fileTools {
            let params = tool.parameterSummary.isEmpty ? "" : " (\(tool.parameterSummary))"
            let destructive = tool.isDestructive ? " [destructive]" : ""
            toolDescriptions.append("- \(tool.name)\(params): \(tool.description)\(destructive)")
        }
        
        // Command tool
        if let cmd = commandTool {
            toolDescriptions.append("\n- \(cmd.name): \(cmd.description) [destructive]")
        }
        
        // Fetch tool
        if let fetch = fetchTool {
            toolDescriptions.append("\n- \(fetch.name): \(fetch.description)")
        }
        
        return """
        You are an AI coding assistant with direct access to the user's filesystem, shell, and HTTP requests.
        Working directory: \(workingDirectory)
        
        Available tools:
        \(toolDescriptions.joined(separator: "\n"))
        
        Guidelines:
        - All file paths are relative to the working directory unless absolute.
        - Always read a file before editing it so you know the current contents.
        - Use edit_file for surgical changes; use write_file only for new files or full rewrites.
        - For run_command, commands execute in the working directory with a 30-second timeout.
        - For fetch, only HTTP/HTTPS URLs are allowed. Private IPs and localhost are blocked for security.
        - Keep the user informed about what you're doing and why.
        - If a tool call fails, explain the error and try an alternative approach.
        """
    }
}

// MARK: - Legacy AgentToolExecutor (delegates to registry)

/// Executes built-in agent tools with path sandboxing.
/// Maintains backward compatibility - now delegates to BuiltInToolRegistry.
actor AgentToolExecutor {
    /// Execute a built-in tool and return the result as a string.
    func execute(toolName: String, arguments: [String: Any], workingDirectory: String) async throws -> String {
        return try await BuiltInToolRegistry.shared.execute(
            toolName: toolName,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }
}

// MARK: - Undo Entry (Dangerous Mode)

/// Tracks a file change made by an agent tool so it can be reverted.
struct UndoEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let toolName: String       // write_file, edit_file, run_command
    let filePath: String       // relative path
    let fullPath: String       // absolute path
    let previousContent: String? // nil if file didn't exist (new file)
    let newContent: String     // content after the change
    let summary: String        // human-readable description
    var isReverted: Bool = false
    
    /// Revert this change: restore previous content or delete the file if it was newly created.
    func revert() throws {
        if let previous = previousContent {
            // File existed before — restore old content
            try previous.write(toFile: fullPath, atomically: true, encoding: .utf8)
        } else {
            // File was newly created — delete it
            if FileManager.default.fileExists(atPath: fullPath) {
                try FileManager.default.removeItem(atPath: fullPath)
            }
        }
    }
}

// MARK: - Pending Tool Confirmation

/// Holds state for a destructive tool call awaiting user confirmation.
struct PendingToolConfirmation: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: [String: Any]
    let displaySummary: String
    let continuation: CheckedContinuation<Bool, Never>
    
    // Rich data for the confirmation UI
    let filePath: String?
    let oldText: String?       // edit_file: text being replaced
    let newText: String?       // edit_file: replacement text
    let fileContent: String?   // write_file: content to write
    let command: String?       // run_command: shell command
    let isNewFile: Bool        // write_file: whether file is new or overwrite
    
    init(
        toolName: String,
        arguments: [String: Any],
        displaySummary: String,
        continuation: CheckedContinuation<Bool, Never>,
        workingDirectory: String? = nil
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.displaySummary = displaySummary
        self.continuation = continuation
        
        let path = arguments["path"] as? String
        self.filePath = path
        self.oldText = arguments["old_text"] as? String
        self.newText = arguments["new_text"] as? String
        self.fileContent = arguments["content"] as? String
        self.command = arguments["command"] as? String
        
        // Check if the file already exists for write_file
        if toolName == "write_file", let path = path {
            let fullPath: String
            if path.hasPrefix("/") {
                fullPath = path
            } else if let wd = workingDirectory {
                fullPath = (wd as NSString).appendingPathComponent(path)
            } else {
                fullPath = path
            }
            self.isNewFile = !FileManager.default.fileExists(atPath: fullPath)
        } else {
            self.isNewFile = false
        }
    }
    
    /// Build a human-readable summary for the confirmation dialog.
    static func summary(toolName: String, arguments: [String: Any]) -> String {
        switch toolName {
        case "write_file":
            let path = arguments["path"] as? String ?? "unknown"
            let content = arguments["content"] as? String ?? ""
            let lines = content.components(separatedBy: "\n").count
            return "Write \(lines) lines to '\(path)'"
        case "edit_file":
            let path = arguments["path"] as? String ?? "unknown"
            let oldText = arguments["old_text"] as? String ?? ""
            let oldLines = oldText.components(separatedBy: "\n").count
            return "Edit '\(path)' (replace \(oldLines) line\(oldLines == 1 ? "" : "s"))"
        case "run_command":
            let command = arguments["command"] as? String ?? ""
            return command
        default:
            return "\(toolName)"
        }
    }
}
