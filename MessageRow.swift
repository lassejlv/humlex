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
            if isStreaming && message.text.isEmpty {
                // Skeleton loading state
                SkeletonView()
                    .frame(maxWidth: 760, alignment: .leading)
            } else {
                MarkdownView(source: message.text, isStreaming: isStreaming)
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: 760, alignment: .leading)
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
