import AppKit
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLastAssistant: Bool
    let onRetry: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.toastManager) private var toast
    @State private var showActions = false
    @State private var hideTask: DispatchWorkItem?
    @State private var toolResultExpanded = false

    init(
        message: ChatMessage,
        isStreaming: Bool,
        isLastAssistant: Bool = false,
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.isLastAssistant = isLastAssistant
        self.onRetry = onRetry
    }

    private var isUser: Bool {
        message.role == .user
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
        .padding(.vertical, 4)
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Attachment chips
            if !message.attachments.isEmpty {
                messageAttachments(alignment: .trailing)
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .foregroundStyle(theme.userBubbleText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 580, alignment: .trailing)
            }

            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isStreaming && message.text.isEmpty && (message.toolCalls ?? []).isEmpty {
                // Skeleton loading state
                SkeletonView()
                    .frame(maxWidth: 760, alignment: .leading)
            } else {
                if !message.text.isEmpty {
                    MarkdownView(source: message.text, isStreaming: isStreaming)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .frame(maxWidth: 760, alignment: .leading)
                }

                // Show tool calls if present
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    toolCallsView(toolCalls)
                }
            }

            // Action bar: timestamp + copy + retry
            HStack(spacing: 4) {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)

                if !isStreaming {
                    actionButtons
                        .opacity(showActions ? 1 : 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hideTask?.cancel()
                hideTask = nil
                withAnimation(.easeInOut(duration: 0.12)) {
                    showActions = true
                }
            } else {
                // Small delay before hiding so cursor can travel to the buttons
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

    @ViewBuilder
    private func toolCallsView(_ toolCalls: [ChatMessage.ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(toolCalls, id: \.id) { tc in
                let isBuiltIn = AgentTools.isBuiltIn(serverName: tc.serverName)
                let isCLIProvider = Self.isCLIProviderTool(serverName: tc.serverName)
                let isKnownTool = isBuiltIn || isCLIProvider
                let args = parseToolArgs(tc.arguments)

                VStack(alignment: .leading, spacing: 0) {
                    // Main chip row
                    HStack(spacing: 6) {
                        Image(systemName: isKnownTool ? toolCallIcon(tc.name) : "wrench.and.screwdriver")
                            .font(.system(size: 11))
                            .foregroundStyle(isBuiltIn ? .orange : (isCLIProvider ? .purple : theme.accent))
                        Text(isKnownTool ? (AgentToolName(rawValue: tc.name)?.displayName ?? tc.name) : tc.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)

                        // Inline argument summary
                        if let summary = toolCallArgSummary(tc.name, args: args) {
                            Text(summary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if !tc.serverName.isEmpty {
                            Text(isBuiltIn ? "Agent" : tc.serverName)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.chipBackground, in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.codeBorder, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    /// Check if a server name belongs to a CLI provider (tools are informational only).
    private static func isCLIProviderTool(serverName: String) -> Bool {
        serverName == "Codex" || serverName == "Claude Code"
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
        let isBuiltIn = message.toolName.map { AgentToolName(rawValue: $0) != nil } ?? false
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
                    Image(systemName: toolResultIcon(for: message.toolName, isError: isError, isDenied: isDenied))
                        .font(.system(size: 11))
                        .foregroundStyle(toolResultIconColor(isError: isError, isDenied: isDenied, isBuiltIn: isBuiltIn))

                    // Tool name
                    if isBuiltIn, let name = message.toolName, let displayName = AgentToolName(rawValue: name)?.displayName {
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
                    if isDenied {
                        Text("denied")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.7))
                    } else if isError {
                        Text("error")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.7))
                    } else if isCommand {
                        // Show exit code inline
                        if let exitLine = lines.first, exitLine.hasPrefix("Exit code:") {
                            let code = exitLine.replacingOccurrences(of: "Exit code: ", with: "").trimmingCharacters(in: .whitespaces)
                            Text("exit \(code)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(code == "0" ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
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
                        Text(message.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.85))
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
                        Text(message.text)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    } else {
                        // Code block for read_file, search_files, list_directory, MCP
                        Text(message.text)
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
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.codeBackground.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.codeBorder.opacity(0.5), lineWidth: 1)
        )
        .frame(maxWidth: 760, alignment: .leading)
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

// MARK: - Skeleton Loading View

struct SkeletonView: View {
    @Environment(\.appTheme) private var theme
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            skeletonLine(width: 280)
            skeletonLine(width: 220)
            skeletonLine(width: 250)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 2
            }
        }
    }

    private func skeletonLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(theme.textTertiary.opacity(0.15))
            .frame(width: width, height: 12)
            .overlay(
                GeometryReader { geo in
                    let shimmerWidth = geo.size.width * 0.6
                    LinearGradient(
                        colors: [
                            .clear,
                            theme.textSecondary.opacity(0.12),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: shimmerWidth)
                    .offset(x: shimmerOffset * geo.size.width - shimmerWidth / 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            )
    }
}
