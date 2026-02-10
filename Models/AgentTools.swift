import Foundation

// MARK: - Agent Tool Definitions

/// Built-in tools available when agent mode is enabled.
enum AgentToolName: String, CaseIterable {
    case readFile = "read_file"
    case writeFile = "write_file"
    case editFile = "edit_file"
    case listDirectory = "list_directory"
    case searchFiles = "search_files"
    case runCommand = "run_command"

    var displayName: String {
        switch self {
        case .readFile: return "Read File"
        case .writeFile: return "Write File"
        case .editFile: return "Edit File"
        case .listDirectory: return "List Directory"
        case .searchFiles: return "Search Files"
        case .runCommand: return "Run Command"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .writeFile, .editFile, .runCommand: return true
        case .readFile, .listDirectory, .searchFiles: return false
        }
    }
}

/// Provides built-in tool definitions and execution for agent mode.
enum AgentTools {
    /// Sentinel server name used to identify built-in tools vs MCP tools.
    static let builtInServerName = "__builtin__"

    /// Check if a tool call is a built-in agent tool (vs an MCP tool).
    static func isBuiltIn(serverName: String) -> Bool {
        serverName == builtInServerName
    }

    /// Check if a built-in tool is destructive and needs user confirmation.
    static func isDestructive(_ toolName: String) -> Bool {
        AgentToolName(rawValue: toolName)?.isDestructive ?? false
    }

    /// Generate MCPTool definitions for all built-in tools.
    static func definitions() -> [MCPTool] {
        return AgentToolName.allCases.map { tool in
            MCPTool(
                serverName: builtInServerName,
                name: tool.rawValue,
                description: toolDescription(tool),
                inputSchema: toolSchema(tool)
            )
        }
    }

    /// System prompt injected when agent mode is active.
    static func systemPrompt(workingDirectory: String) -> String {
        """
        You are an AI coding assistant with direct access to the user's filesystem and shell.
        Working directory: \(workingDirectory)

        You have these tools available:
        - read_file: Read the contents of a file. Use this before editing files.
        - write_file: Create a new file or overwrite an existing file entirely.
        - edit_file: Make targeted changes to a file by replacing specific text. Preferred over write_file for modifications.
        - list_directory: List files and folders in a directory.
        - search_files: Search for a regex pattern across files recursively.
        - run_command: Execute a shell command and get stdout/stderr output.

        Guidelines:
        - All file paths are relative to the working directory unless absolute.
        - Always read a file before editing it so you know the current contents.
        - Use edit_file for surgical changes; use write_file only for new files or full rewrites.
        - For run_command, commands execute in the working directory with a 30-second timeout.
        - Keep the user informed about what you're doing and why.
        - If a tool call fails, explain the error and try an alternative approach.
        """
    }

    // MARK: - Tool Descriptions

    private static func toolDescription(_ tool: AgentToolName) -> String {
        switch tool {
        case .readFile:
            return "Read the contents of a file at the given path. Returns the file content as text."
        case .writeFile:
            return "Create or overwrite a file at the given path with the provided content."
        case .editFile:
            return "Edit a file by replacing an exact text match with new text. The old_text must match exactly (including whitespace and indentation)."
        case .listDirectory:
            return "List the contents of a directory. Returns file names, types, and sizes."
        case .searchFiles:
            return "Search for a regex pattern across files in a directory recursively. Returns matching file paths and line contents."
        case .runCommand:
            return "Execute a shell command in the working directory. Returns stdout and stderr. Commands have a 30-second timeout."
        }
    }

    // MARK: - Tool Schemas (JSON Schema format)

    private static func toolSchema(_ tool: AgentToolName) -> [String: AnyCodable] {
        switch tool {
        case .readFile:
            return [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "path": ["type": "string", "description": "Path to the file to read (relative to working directory)"]
                ] as [String: Any]),
                "required": AnyCodable(["path"])
            ]
        case .writeFile:
            return [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "path": ["type": "string", "description": "Path to the file to write (relative to working directory)"],
                    "content": ["type": "string", "description": "Content to write to the file"]
                ] as [String: Any]),
                "required": AnyCodable(["path", "content"])
            ]
        case .editFile:
            return [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "path": ["type": "string", "description": "Path to the file to edit (relative to working directory)"],
                    "old_text": ["type": "string", "description": "Exact text to find in the file (must match exactly including whitespace)"],
                    "new_text": ["type": "string", "description": "Text to replace the old_text with"]
                ] as [String: Any]),
                "required": AnyCodable(["path", "old_text", "new_text"])
            ]
        case .listDirectory:
            return [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "path": ["type": "string", "description": "Directory path to list (relative to working directory, defaults to \".\")"]
                ] as [String: Any]),
                "required": AnyCodable([] as [String])
            ]
        case .searchFiles:
            return [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "pattern": ["type": "string", "description": "Regex pattern to search for in file contents"],
                    "path": ["type": "string", "description": "Directory to search in (relative to working directory, defaults to \".\")"]
                ] as [String: Any]),
                "required": AnyCodable(["pattern"])
            ]
        case .runCommand:
            return [
                "type": AnyCodable("object"),
                "properties": AnyCodable([
                    "command": ["type": "string", "description": "Shell command to execute"]
                ] as [String: Any]),
                "required": AnyCodable(["command"])
            ]
        }
    }
}

// MARK: - Agent Tool Executor

/// Executes built-in agent tools with path sandboxing.
actor AgentToolExecutor {
    /// Execute a built-in tool and return the result as a string.
    func execute(toolName: String, arguments: [String: Any], workingDirectory: String) async throws -> String {
        guard let tool = AgentToolName(rawValue: toolName) else {
            return "Error: Unknown tool '\(toolName)'"
        }

        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL

        switch tool {
        case .readFile:
            return try executeReadFile(arguments: arguments, workDir: workDir)
        case .writeFile:
            return try executeWriteFile(arguments: arguments, workDir: workDir)
        case .editFile:
            return try executeEditFile(arguments: arguments, workDir: workDir)
        case .listDirectory:
            return try executeListDirectory(arguments: arguments, workDir: workDir)
        case .searchFiles:
            return try await executeSearchFiles(arguments: arguments, workDir: workDir)
        case .runCommand:
            return try await executeRunCommand(arguments: arguments, workDir: workDir)
        }
    }

    // MARK: - Tool Implementations

    private func executeReadFile(arguments: [String: Any], workDir: URL) throws -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }

        let fileURL = try resolveAndSandbox(path: path, workDir: workDir)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return "Error: File not found at '\(path)'"
        }

        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            return "Error: File is not valid UTF-8 text"
        }

        let lines = content.components(separatedBy: "\n")
        return "File: \(path) (\(lines.count) lines, \(data.count) bytes)\n\n\(content)"
    }

    private func executeWriteFile(arguments: [String: Any], workDir: URL) throws -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let content = arguments["content"] as? String else {
            return "Error: Missing required parameter 'content'"
        }

        let fileURL = try resolveAndSandbox(path: path, workDir: workDir)

        // Create parent directories if needed
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let existed = FileManager.default.fileExists(atPath: fileURL.path)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let lines = content.components(separatedBy: "\n").count
        return existed
            ? "Overwrote '\(path)' (\(lines) lines, \(content.utf8.count) bytes)"
            : "Created '\(path)' (\(lines) lines, \(content.utf8.count) bytes)"
    }

    private func executeEditFile(arguments: [String: Any], workDir: URL) throws -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let oldText = arguments["old_text"] as? String else {
            return "Error: Missing required parameter 'old_text'"
        }
        guard let newText = arguments["new_text"] as? String else {
            return "Error: Missing required parameter 'new_text'"
        }

        let fileURL = try resolveAndSandbox(path: path, workDir: workDir)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return "Error: File not found at '\(path)'"
        }

        let data = try Data(contentsOf: fileURL)
        guard var content = String(data: data, encoding: .utf8) else {
            return "Error: File is not valid UTF-8 text"
        }

        let occurrences = content.components(separatedBy: oldText).count - 1
        if occurrences == 0 {
            // Show a snippet of the file to help the model
            let preview = String(content.prefix(500))
            return "Error: old_text not found in '\(path)'. File starts with:\n\(preview)"
        }
        if occurrences > 1 {
            return "Error: old_text found \(occurrences) times in '\(path)'. Provide more context to make it unique."
        }

        content = content.replacingOccurrences(of: oldText, with: newText)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let oldLines = oldText.components(separatedBy: "\n").count
        let newLines = newText.components(separatedBy: "\n").count
        return "Edited '\(path)': replaced \(oldLines) line\(oldLines == 1 ? "" : "s") with \(newLines) line\(newLines == 1 ? "" : "s")"
    }

    private func executeListDirectory(arguments: [String: Any], workDir: URL) throws -> String {
        let path = arguments["path"] as? String ?? "."
        let dirURL = try resolveAndSandbox(path: path, workDir: workDir)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return "Error: '\(path)' is not a directory or does not exist"
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        if contents.isEmpty {
            return "Directory '\(path)' is empty"
        }

        let sorted = contents.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var lines: [String] = ["Directory: \(path) (\(sorted.count) items)\n"]
        for url in sorted {
            let resources = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resources?.isDirectory ?? false
            let size = resources?.fileSize ?? 0

            if isDirectory {
                lines.append("  \(url.lastPathComponent)/")
            } else {
                let sizeStr = formatFileSize(size)
                lines.append("  \(url.lastPathComponent)  (\(sizeStr))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func executeSearchFiles(arguments: [String: Any], workDir: URL) async throws -> String {
        guard let pattern = arguments["pattern"] as? String else {
            return "Error: Missing required parameter 'pattern'"
        }
        let path = arguments["path"] as? String ?? "."
        let dirURL = try resolveAndSandbox(path: path, workDir: workDir)

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return "Error: Invalid regex pattern '\(pattern)'"
        }

        var results: [(file: String, line: Int, content: String)] = []
        let maxResults = 50

        try searchRecursive(
            directory: dirURL,
            regex: regex,
            basePath: dirURL,
            results: &results,
            maxResults: maxResults
        )

        if results.isEmpty {
            return "No matches found for pattern '\(pattern)' in '\(path)'"
        }

        var output = "Found \(results.count) match\(results.count == 1 ? "" : "es") for '\(pattern)':\n\n"
        for match in results {
            output += "\(match.file):\(match.line): \(match.content)\n"
        }
        if results.count >= maxResults {
            output += "\n(Results truncated at \(maxResults) matches)"
        }
        return output
    }

    private func executeRunCommand(arguments: [String: Any], workDir: URL) async throws -> String {
        guard let command = arguments["command"] as? String else {
            return "Error: Missing required parameter 'command'"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workDir

        // Inherit a useful PATH
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            // Timeout after 30 seconds
            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)

            do {
                try process.run()
                process.waitUntilExit()
                timeoutItem.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus

                var output = ""
                if !stdout.isEmpty {
                    output += stdout
                }
                if !stderr.isEmpty {
                    if !output.isEmpty { output += "\n" }
                    output += "[stderr]\n\(stderr)"
                }
                if output.isEmpty {
                    output = "(no output)"
                }

                // Truncate very long outputs
                if output.count > 50_000 {
                    output = String(output.prefix(50_000)) + "\n\n(output truncated at 50,000 characters)"
                }

                let header = "Exit code: \(exitCode)\n\n"
                continuation.resume(returning: header + output)
            } catch {
                timeoutItem.cancel()
                continuation.resume(returning: "Error running command: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    /// Resolve a path relative to the working directory and ensure it stays within the sandbox.
    private func resolveAndSandbox(path: String, workDir: URL) throws -> URL {
        let resolved: URL
        if path.hasPrefix("/") {
            resolved = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            resolved = workDir.appendingPathComponent(path).standardizedFileURL
        }

        let resolvedPath = resolved.path
        let workDirPath = workDir.path

        // Allow the working directory itself and anything under it
        guard resolvedPath == workDirPath || resolvedPath.hasPrefix(workDirPath + "/") else {
            throw AgentToolError.pathOutsideSandbox(path)
        }

        return resolved
    }

    private func searchRecursive(
        directory: URL,
        regex: NSRegularExpression,
        basePath: URL,
        results: inout [(file: String, line: Int, content: String)],
        maxResults: Int
    ) throws {
        guard results.count < maxResults else { return }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for url in contents {
            guard results.count < maxResults else { return }

            let resources = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if resources?.isDirectory == true {
                // Skip common non-useful directories
                let name = url.lastPathComponent
                if ["node_modules", ".git", ".build", "build", "DerivedData", ".next", "dist", "__pycache__"].contains(name) {
                    continue
                }
                try searchRecursive(directory: url, regex: regex, basePath: basePath, results: &results, maxResults: maxResults)
            } else {
                // Only search text-like files
                let ext = url.pathExtension.lowercased()
                let textExtensions = Set([
                    "swift", "py", "rs", "ts", "tsx", "jsx", "js", "css", "html", "json",
                    "md", "txt", "yml", "yaml", "toml", "sh", "bash", "c", "cpp", "h", "hpp",
                    "go", "rb", "java", "kt", "sql", "xml", "csv", "log", "env", "conf",
                    "cfg", "ini", "makefile", "dockerfile", "gitignore", "editorconfig"
                ])
                let noExt = ext.isEmpty
                guard textExtensions.contains(ext) || noExt else { continue }

                guard let data = try? Data(contentsOf: url),
                      data.count < 1_000_000, // Skip files > 1MB
                      let content = String(data: data, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: "\n")
                let relativePath = url.path.replacingOccurrences(of: basePath.path + "/", with: "")

                for (lineIdx, line) in lines.enumerated() {
                    guard results.count < maxResults else { return }
                    let range = NSRange(line.startIndex..., in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        results.append((file: relativePath, line: lineIdx + 1, content: line.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        }
    }

    private func formatFileSize(_ size: Int) -> String {
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return "\(size / 1024) KB"
        } else {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        }
    }
}

// MARK: - Errors

enum AgentToolError: LocalizedError {
    case pathOutsideSandbox(String)

    var errorDescription: String? {
        switch self {
        case .pathOutsideSandbox(let path):
            return "Path '\(path)' is outside the working directory. Access denied."
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
