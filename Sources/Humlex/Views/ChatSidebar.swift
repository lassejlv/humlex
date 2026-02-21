import Foundation
import SwiftUI

struct ThreadRow: View {
    let thread: ChatThread
    let isSelected: Bool
    let isPinned: Bool

    @Environment(\.appTheme) private var theme

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var subtitle: String {
        if let lastMessage = thread.messages.last {
            let trimmed = lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !lastMessage.attachments.isEmpty {
                    return "\(lastMessage.attachments.count) attachment\(lastMessage.attachments.count == 1 ? "" : "s")"
                }
                return "No message text"
            }
            return trimmed.replacingOccurrences(of: "\n", with: " ")
        }
        return "No messages yet"
    }

    private var lastUpdatedText: String {
        guard let lastDate = thread.messages.last?.timestamp else { return "New" }
        return Self.relativeFormatter.localizedString(for: lastDate, relativeTo: Date())
    }

    private var modelName: String? {
        guard let reference = thread.modelReference, !reference.isEmpty else { return nil }
        let parts = reference.components(separatedBy: "::")
        return parts.count == 2 ? parts[1] : reference
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(thread.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                if thread.agentEnabled {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(thread.dangerousMode ? Color.red : theme.accent)
                }

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: 0)

                Text(lastUpdatedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label("\(thread.messages.count)", systemImage: "text.bubble")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)

                if let modelName {
                    Text(modelName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}
