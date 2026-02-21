import Foundation
import AppKit
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isAgentMode: Bool
    let isLastAssistant: Bool
    let mergedToolResultsByCallID: [String: ChatMessage]
    let onRetry: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.toastManager) private var toast
    @AppStorage("chat_font_size") private var chatFontSize = 13.0
    @AppStorage("tool_ui_compact_mode") private var isToolCompactMode = true
    @State private var showActions = false
    @State private var hideTask: DispatchWorkItem?
    @State private var toolResultExpanded = false
    @State private var expandedToolCallIDs: Set<String> = []
    @State private var expandedMergedResultCallIDs: Set<String> = []
    @State private var showFullToolResultOutput = false

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        message: ChatMessage,
        isStreaming: Bool,
        isAgentMode: Bool = false,
        isLastAssistant: Bool = false,
        mergedToolResultsByCallID: [String: ChatMessage] = [:],
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.isAgentMode = isAgentMode
        self.isLastAssistant = isLastAssistant
        self.mergedToolResultsByCallID = mergedToolResultsByCallID
        self.onRetry = onRetry
        _toolResultExpanded = State(initialValue: Self.initialToolResultExpanded(for: message))
    }

    private static func initialToolResultExpanded(for message: ChatMessage) -> Bool {
        guard message.role == .tool else { return false }
        if message.text == "User denied this operation." { return true }
        if message.text.hasPrefix("Error:") { return true }
        if message.toolName == "run_command",
            let firstLine = message.text.components(separatedBy: "\n").first,
            firstLine.hasPrefix("Exit code:")
        {
            let code = firstLine.replacingOccurrences(of: "Exit code:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return code != "0"
        }
        return false
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var resolvedChatFontSize: CGFloat {
        CGFloat(min(max(chatFontSize, 11), 20))
    }

    private var messageTimestampLabel: String {
        Self.timestampFormatter.string(from: message.timestamp)
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 0)
                userBubble
            } else if message.role == .tool {
                toolResultBlock
                Spacer(minLength: 0)
            } else {
                assistantBlock
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hideTask?.cancel()
                hideTask = nil
                withAnimation(.easeInOut(duration: 0.12)) {
                    showActions = true
                }
            } else {
                let task = DispatchWorkItem {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showActions = false
                    }
                }
                hideTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
            }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Attachment chips
            if !message.attachments.isEmpty {
                messageAttachments(alignment: .trailing)
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: resolvedChatFontSize))
                    .foregroundStyle(theme.userBubbleText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 580, alignment: .trailing)
            }

            Text(messageTimestampLabel)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .padding(.trailing, 2)
                .opacity(showActions ? 1 : 0)
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isStreaming && message.text.isEmpty && (message.toolCalls ?? []).isEmpty {
                ThinkingIndicatorView(
                    label: isAgentMode ? "Agent is working" : "Thinking"
                )
            } else {
                if !message.text.isEmpty {
                    MarkdownView(source: message.text, isStreaming: isStreaming)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .frame(maxWidth: 760, alignment: .leading)
                }

                // Show tool calls if present
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    toolCallsView(toolCalls, resultsByCallID: mergedToolResultsByCallID)
                }
            }

            // Action bar: copy + retry
            let hasVisibleAssistantText = !message.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            if !isStreaming && hasVisibleAssistantText {
                HStack(spacing: 4) {
                    actionButtons
                        .opacity(showActions ? 1 : 0)
                    Text(messageTimestampLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .opacity(showActions ? 1 : 0)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func toolCallsView(
        _ toolCalls: [ChatMessage.ToolCall],
        resultsByCallID: [String: ChatMessage]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Tool Steps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)

                Text("\(toolCalls.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.chipBackground, in: Capsule())

                Spacer(minLength: 0)

                Button {
                    isToolCompactMode.toggle()
                } label: {
                    Label(isToolCompactMode ? "Compact" : "Detailed", systemImage: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Toggle tool steps density")
            }

            ForEach(Array(toolCalls.enumerated()), id: \.element.id) { index, tc in
                let isBuiltIn = AgentTools.isBuiltIn(serverName: tc.serverName)
                let isCLIProvider = Self.isCLIProviderTool(serverName: tc.serverName)
                let isKnownTool = isBuiltIn || isCLIProvider
                let args = parseToolArgs(tc.arguments)
                let isExpanded = expandedToolCallIDs.contains(tc.id)
                let mergedResult = resultsByCallID[tc.id]
                let mergedText = mergedResult?.text ?? ""
                let mergedLines = mergedText.components(separatedBy: "\n")
                let mergedIsError = mergedText.hasPrefix("Error:") || mergedText == "User denied this operation."
                let mergedIsExpanded = expandedMergedResultCallIDs.contains(tc.id)
                let stepDurationLabel = mergedResult.map { result in
                    durationLabel(from: message.timestamp, to: result.timestamp)
                }
                let hasNextStep = index < toolCalls.count - 1

                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(theme.textTertiary.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .padding(.top, 10)

                        if hasNextStep {
                            Rectangle()
                                .fill(theme.codeBorder.opacity(0.65))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .padding(.top, 4)
                        }
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                                .frame(minWidth: 18)

                            Image(systemName: isKnownTool ? toolCallIcon(tc.name) : "wrench.and.screwdriver")
                                .font(.system(size: 11))
                                .foregroundStyle(isBuiltIn ? .orange : (isCLIProvider ? .purple : theme.accent))

                            Text(isKnownTool ? (toolDisplayName(tc.name) ?? tc.name) : tc.name)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)

                            if let summary = toolCallArgSummary(tc.name, args: args), !summary.isEmpty {
                                Text(summary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 0)

                            Text(mergedResult == nil ? (isStreaming ? "Running" : "Queued") : (mergedIsError ? "Failed" : "Completed"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(mergedResult == nil ? (isStreaming ? Color.orange : theme.textTertiary) : (mergedIsError ? Color.red : Color.green))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((mergedResult == nil ? (isStreaming ? Color.orange : theme.chipBackground) : (mergedIsError ? Color.red : Color.green)).opacity(0.14), in: Capsule())

                            if let stepDurationLabel {
                                Text(stepDurationLabel)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.textTertiary)
                            }

                            if !tc.serverName.isEmpty {
                                Text(isBuiltIn ? "Agent" : tc.serverName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(theme.chipBackground, in: Capsule())
                            }

                            if !isToolCompactMode, !args.isEmpty {
                                Button {
                                    if isExpanded {
                                        expandedToolCallIDs.remove(tc.id)
                                    } else {
                                        expandedToolCallIDs.insert(tc.id)
                                    }
                                } label: {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(theme.textTertiary)
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(.plain)
                                .help("Show tool arguments")
                            }

                            if mergedResult != nil {
                                Button {
                                    if mergedIsExpanded {
                                        expandedMergedResultCallIDs.remove(tc.id)
                                    } else {
                                        expandedMergedResultCallIDs.insert(tc.id)
                                    }
                                } label: {
                                    Image(systemName: mergedIsExpanded ? "doc.text.fill" : "doc.text")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(theme.textTertiary)
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(.plain)
                                .help("Show tool output")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                        if !isToolCompactMode, isExpanded, !args.isEmpty {
                            Text(prettyPrintedJSON(tc.arguments) ?? tc.arguments)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                        }

                        if mergedIsExpanded, !mergedText.isEmpty {
                            let previewLines = isToolCompactMode && mergedLines.count > 30
                                ? Array(mergedLines.prefix(30))
                                : mergedLines
                            Text(previewLines.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(mergedIsError ? Color.red.opacity(0.85) : theme.textSecondary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)

                            if isToolCompactMode && mergedLines.count > 30 {
                                Text("Showing first 30 lines")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.codeBorder, lineWidth: 1)
                    )
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    /// Legacy hook for informational tool events. Currently unused.
    private static func isCLIProviderTool(serverName: String) -> Bool {
        _ = serverName
        return false
    }

    private func toolCallIcon(_ name: String) -> String {
        switch name {
        case "read_file": return "doc.text"
        case "write_file": return "doc.badge.plus"
        case "edit_file": return "pencil.line"
        case "list_directory": return "folder"
        case "search_files": return "doc.text.magnifyingglass"
        case "run_command": return "terminal"
        default: return "terminal"
        }
    }

    private func parseToolArgs(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    private func toolCallArgSummary(_ name: String, args: [String: Any]) -> String? {
        switch name {
        case "read_file", "write_file", "edit_file":
            return args["path"] as? String
        case "list_directory":
            let path = args["path"] as? String ?? "."
            return path
        case "search_files":
            if let pattern = args["pattern"] as? String {
                return "/\(pattern)/"
            }
            return nil
        case "run_command":
            if let cmd = args["command"] as? String {
                // Show first 60 chars of command
                let summary = cmd.count > 60 ? String(cmd.prefix(60)) + "..." : cmd
                // Append status if available (from CLI providers)
                if let status = args["status"] as? String, !status.isEmpty, status != "0" {
                    return "\(summary) (exit: \(status))"
                }
                return summary
            }
            return nil
        default:
            // For unknown CLI tool types, show a summary of the first string value
            if let firstValue = args.values.first(where: { $0 is String }) as? String {
                return firstValue.count > 60 ? String(firstValue.prefix(60)) + "..." : firstValue
            }
            return nil
        }
    }

    private var toolResultBlock: some View {
        let isBuiltIn =
            message.toolName.map { BuiltInToolRegistry.shared.hasTool(named: $0) } ?? false
        let isCommand = message.toolName == "run_command"
        let isFileRead = message.toolName == "read_file"
        let isSearch = message.toolName == "search_files"
        let isFileWrite = message.toolName == "write_file"
        let isEdit = message.toolName == "edit_file"
        let isListDir = message.toolName == "list_directory"
        let isDenied = message.text == "User denied this operation."
        let isError = message.text.hasPrefix("Error:")
        let lines = message.text.components(separatedBy: "\n")
        let lineCount = lines.count
        let resultState = toolResultState(
            isError: isError, isDenied: isDenied, isCommand: isCommand, lines: lines)
        let displayText = toolResultDisplayText(lines: lines)
        let shouldShowOutputToggle = lines.count > 40

        return VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    toolResultExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // Expand/collapse chevron
                    Image(systemName: toolResultExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 12)

                    // Tool icon
                    Image(
                        systemName: toolResultIcon(
                            for: message.toolName, isError: isError, isDenied: isDenied)
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        toolResultIconColor(
                            isError: isError, isDenied: isDenied, isBuiltIn: isBuiltIn))

                    // Tool name
                    if isBuiltIn, let name = message.toolName,
                        let displayName = toolDisplayName(name)
                    {
                        Text(displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Text("Tool Result")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        if let name = message.toolName {
                            Text(name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }

                    // Inline status/summary
                    if isCommand {
                        // Show exit code inline
                        if let exitLine = lines.first, exitLine.hasPrefix("Exit code:") {
                            let code = exitLine.replacingOccurrences(of: "Exit code: ", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            Text("exit \(code)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(
                                    code == "0" ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                        }
                    } else if isFileRead || isSearch || isListDir {
                        Text("\(lineCount) lines")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    } else if isFileWrite || isEdit {
                        // Show the compact result inline
                        Text(message.text.prefix(80))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Text(toolResultStateLabel(resultState))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(toolResultStateColor(resultState))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(toolResultStateColor(resultState).opacity(0.12), in: Capsule())

                    Button {
                        isToolCompactMode.toggle()
                    } label: {
                        Image(systemName: isToolCompactMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isToolCompactMode ? "Switch to detailed tool output" : "Switch to compact tool output")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        toast.show(.success("Tool result copied"))
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Copy tool result")

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if toolResultExpanded {
                Group {
                    if isDenied {
                        Text("Operation was denied by user.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    } else if isCommand {
                        // Terminal-styled block
                        Text(displayText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(
                                resultState == .error
                                    ? Color.red.opacity(0.85) : Color.green.opacity(0.85)
                            )
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
                            )
                            .padding(.horizontal, 10)
                    } else if isFileWrite || isEdit {
                        Text(displayText)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    } else {
                        // Code block for read_file, search_files, list_directory, MCP
                        Text(displayText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.codeBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(theme.codeBorder, lineWidth: 1)
                            )
                            .padding(.horizontal, 10)
                    }

                    if isToolCompactMode, shouldShowOutputToggle {
                        HStack {
                            Spacer(minLength: 0)
                            Button(showFullToolResultOutput ? "Show condensed" : "Show full output") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showFullToolResultOutput.toggle()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)
                        }
                    }
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.codeBackground.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.codeBorder.opacity(0.5), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(toolResultStateColor(resultState).opacity(0.85))
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private enum ToolResultState {
        case success
        case warning
        case error
    }

    private func toolResultState(isError: Bool, isDenied: Bool, isCommand: Bool, lines: [String])
        -> ToolResultState
    {
        if isDenied || isError { return .error }
        if isCommand,
            let exitLine = lines.first,
            exitLine.hasPrefix("Exit code:")
        {
            let code = exitLine.replacingOccurrences(of: "Exit code:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return code == "0" ? .success : .error
        }
        return .success
    }

    private func toolResultStateLabel(_ state: ToolResultState) -> String {
        switch state {
        case .success: return "Completed"
        case .warning: return "Warning"
        case .error: return "Failed"
        }
    }

    private func toolResultStateColor(_ state: ToolResultState) -> Color {
        switch state {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func toolResultIcon(for toolName: String?, isError: Bool, isDenied: Bool) -> String {
        if isDenied { return "xmark.circle" }
        if isError { return "exclamationmark.triangle" }
        switch toolName {
        case "read_file": return "doc.text"
        case "write_file": return "doc.badge.plus"
        case "edit_file": return "pencil.line"
        case "list_directory": return "folder"
        case "search_files": return "doc.text.magnifyingglass"
        case "run_command": return "terminal"
        default: return "arrow.turn.down.right"
        }
    }

    private func toolResultIconColor(isError: Bool, isDenied: Bool, isBuiltIn: Bool) -> Color {
        if isDenied || isError { return Color.red.opacity(0.7) }
        return isBuiltIn ? .orange : theme.accent
    }

    private func toolResultDisplayText(lines: [String]) -> String {
        guard isToolCompactMode, !showFullToolResultOutput, lines.count > 40 else {
            return lines.joined(separator: "\n")
        }

        let head = lines.prefix(24)
        let tail = lines.suffix(12)
        let omitted = max(0, lines.count - head.count - tail.count)
        var result = Array(head)
        result.append("... [\(omitted) lines omitted] ...")
        result.append(contentsOf: tail)
        return result.joined(separator: "\n")
    }

    private func prettyPrintedJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(obj),
            let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
            let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }
        return pretty
    }

    private func durationLabel(from start: Date, to end: Date) -> String {
        let interval = max(0, end.timeIntervalSince(start))
        if interval < 1 {
            return String(format: "%.0f ms", interval * 1000)
        }
        if interval < 10 {
            return String(format: "%.1f s", interval)
        }
        return String(format: "%.0f s", interval)
    }

    /// Get the display name for a built-in tool from the registry.
    private func toolDisplayName(_ toolName: String) -> String? {
        // Convert snake_case to Title Case for display
        let components = toolName.split(separator: "_")
        guard !components.isEmpty else { return nil }
        return components.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            // Copy button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                toast.show(.success("Copied to clipboard"))
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy response")

            // Retry button (only on the last assistant message)
            if isLastAssistant, let onRetry {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Retry response")
            }
        }
    }

    @ViewBuilder
    private func messageAttachments(alignment: HorizontalAlignment) -> some View {
        let aligned: Alignment = alignment == .trailing ? .trailing : .leading
        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 4) {
            ForEach(message.attachments) { att in
                attachmentBadge(att)
            }
        }
        .frame(maxWidth: 580, alignment: aligned)
    }

    private func attachmentBadge(_ att: Attachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: att.isImage ? "photo" : (att.isText ? "doc.text" : "doc"))
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            Text(att.fileName)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text(att.fileSizeLabel)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.chipBackground, in: Capsule())
        .overlay(Capsule().stroke(theme.chipBorder, lineWidth: 1))
    }
}

extension MessageRow: Equatable {
    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.isStreaming == rhs.isStreaming
            && lhs.isAgentMode == rhs.isAgentMode
            && lhs.isLastAssistant == rhs.isLastAssistant
            && lhs.mergedToolResultsByCallID == rhs.mergedToolResultsByCallID
            && lhs.message == rhs.message
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicatorView: View {
    @Environment(\.appTheme) private var theme
    @State private var shimmerOffset: CGFloat = -120
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)

            ZStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.9),
                        Color.white.opacity(0.45),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: shimmerOffset)
                .mask(
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                )
                .allowsHitTesting(false)
            }
            .onAppear {
                shimmerOffset = -120
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    shimmerOffset = 120
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.codeBackground.opacity(0.45))
        )
    }
}
