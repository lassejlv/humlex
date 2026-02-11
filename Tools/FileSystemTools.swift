//
//  FileSystemTools.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import Foundation

// MARK: - Path Sandboxing Helper

/// Utility for sandboxing file operations to the working directory.
enum PathSandbox {
    /// Resolve a path relative to the working directory and ensure it stays within the sandbox.
    /// - Parameters:
    ///   - path: The path (relative or absolute) to resolve
    ///   - workDir: The working directory URL
    /// - Returns: Resolved URL within the sandbox
    /// - Throws: AgentToolError.pathOutsideSandbox if path escapes the working directory
    static func resolve(path: String, workDir: URL) throws -> URL {
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
}

enum AgentToolError: LocalizedError {
    case pathOutsideSandbox(String)
    
    var errorDescription: String? {
        switch self {
        case .pathOutsideSandbox(let path):
            return "Path '\(path)' is outside the working directory. Access denied."
        }
    }
}

// MARK: - Read File Tool

struct ReadFileTool: BuiltInTool {
    var name: String { "read_file" }
    
    var description: String {
        "Read the contents of a file at the given path. Returns the file content as text."
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "path": Self.stringProperty(description: "Path to the file to read (relative to working directory)")
        ], required: ["path"])
    }
    
    var isDestructive: Bool { false }
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        
        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let fileURL = try PathSandbox.resolve(path: path, workDir: workDir)
        
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
}

// MARK: - Write File Tool

struct WriteFileTool: BuiltInTool {
    var name: String { "write_file" }
    
    var description: String {
        "Create or overwrite a file at the given path with the provided content."
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "path": Self.stringProperty(description: "Path to the file to write (relative to working directory)"),
            "content": Self.stringProperty(description: "Content to write to the file")
        ], required: ["path", "content"])
    }
    
    var isDestructive: Bool { true }
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let content = arguments["content"] as? String else {
            return "Error: Missing required parameter 'content'"
        }
        
        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let fileURL = try PathSandbox.resolve(path: path, workDir: workDir)
        
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
}

// MARK: - Edit File Tool

struct EditFileTool: BuiltInTool {
    var name: String { "edit_file" }
    
    var description: String {
        "Edit a file by replacing an exact text match with new text. The old_text must match exactly (including whitespace and indentation)."
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "path": Self.stringProperty(description: "Path to the file to edit (relative to working directory)"),
            "old_text": Self.stringProperty(description: "Exact text to find in the file (must match exactly including whitespace)"),
            "new_text": Self.stringProperty(description: "Text to replace the old_text with")
        ], required: ["path", "old_text", "new_text"])
    }
    
    var isDestructive: Bool { true }
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let oldText = arguments["old_text"] as? String else {
            return "Error: Missing required parameter 'old_text'"
        }
        guard let newText = arguments["new_text"] as? String else {
            return "Error: Missing required parameter 'new_text'"
        }
        
        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let fileURL = try PathSandbox.resolve(path: path, workDir: workDir)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return "Error: File not found at '\(path)'"
        }
        
        let data = try Data(contentsOf: fileURL)
        guard var content = String(data: data, encoding: .utf8) else {
            return "Error: File is not valid UTF-8 text"
        }
        
        let occurrences = content.components(separatedBy: oldText).count - 1
        if occurrences == 0 {
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
}

// MARK: - List Directory Tool

struct ListDirectoryTool: BuiltInTool {
    var name: String { "list_directory" }
    
    var description: String {
        "List the contents of a directory. Returns file names, types, and sizes."
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "path": Self.stringProperty(description: "Directory path to list (relative to working directory, defaults to \".\")")
        ], required: [])
    }
    
    var isDestructive: Bool { false }
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        let path = arguments["path"] as? String ?? "."
        
        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let dirURL = try PathSandbox.resolve(path: path, workDir: workDir)
        
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

// MARK: - Search Files Tool

struct SearchFilesTool: BuiltInTool {
    var name: String { "search_files" }
    
    var description: String {
        "Search for a regex pattern across files in a directory recursively. Returns matching file paths and line contents."
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "pattern": Self.stringProperty(description: "Regex pattern to search for in file contents"),
            "path": Self.stringProperty(description: "Directory to search in (relative to working directory, defaults to \".\")")
        ], required: ["pattern"])
    }
    
    var isDestructive: Bool { false }
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        guard let pattern = arguments["pattern"] as? String else {
            return "Error: Missing required parameter 'pattern'"
        }
        let path = arguments["path"] as? String ?? "."
        
        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let dirURL = try PathSandbox.resolve(path: path, workDir: workDir)
        
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
                let name = url.lastPathComponent
                if ["node_modules", ".git", ".build", "build", "DerivedData", ".next", "dist", "__pycache__"].contains(name) {
                    continue
                }
                try searchRecursive(directory: url, regex: regex, basePath: basePath, results: &results, maxResults: maxResults)
            } else {
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
                      data.count < 1_000_000,
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
}

// MARK: - Run Command Tool

struct RunCommandTool: BuiltInTool {
    var name: String { "run_command" }
    
    var description: String {
        "Execute a shell command in the working directory. Returns stdout and stderr. Commands have a 30-second timeout."
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "command": Self.stringProperty(description: "Shell command to execute")
        ], required: ["command"])
    }
    
    var isDestructive: Bool { true }
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        guard let command = arguments["command"] as? String else {
            return "Error: Missing required parameter 'command'"
        }
        
        let workDir = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        
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
}
