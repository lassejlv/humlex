import SwiftUI

struct ThreadRow: View {
    let thread: ChatThread
    let isSelected: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thread.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            if let lastMessage = thread.messages.last {
                Text(lastMessage.text)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
