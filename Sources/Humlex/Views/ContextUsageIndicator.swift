import SwiftUI

/// A circular progress indicator showing context window usage with a popover for details.
struct ContextUsageIndicator: View {
    let usage: ThreadTokenUsage?
    let isSending: Bool
    
    @State private var isShowingPopover = false
    @Environment(\.appTheme) private var theme
    
    private var percentage: Double {
        usage?.usagePercentage ?? 0.0
    }
    
    private var usageLevel: UsageLevel {
        UsageLevel(percentage: percentage)
    }
    
    private var displayPercentage: String {
        String(format: "%.0f%%", percentage * 100)
    }
    
    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            ZStack {
                // Background circle
                Circle()
                    .stroke(
                        usageLevel == .normal ? theme.textTertiary.opacity(0.2) :
                        usageLevel == .warning ? Color.yellow.opacity(0.3) :
                        usageLevel == .caution ? Color.orange.opacity(0.3) :
                        Color.red.opacity(0.3),
                        lineWidth: 3
                    )
                    .frame(width: 24, height: 24)
                
                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(min(percentage, 1.0)))
                    .stroke(
                        usageColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))
                
                // Percentage text (small) or icon for high usage
                if percentage > 0.9 {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(usageColor)
                } else {
                    Text(displayPercentage)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(usageColor)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Context window usage: \(displayPercentage)")
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            ContextUsagePopover(usage: usage, isSending: isSending)
                .frame(width: 280)
        }
        .opacity(usage == nil ? 0.5 : 1.0)
    }
    
    private var usageColor: Color {
        switch usageLevel {
        case .normal:
            return theme.accent
        case .warning:
            return .yellow
        case .caution:
            return .orange
        case .danger:
            return .red
        }
    }
}

/// Detailed popover view showing token usage breakdown.
struct ContextUsagePopover: View {
    let usage: ThreadTokenUsage?
    let isSending: Bool
    
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    private var percentage: Double {
        usage?.usagePercentage ?? 0.0
    }
    
    private var usageLevel: UsageLevel {
        UsageLevel(percentage: percentage)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: usageLevel.systemColor)
                    .font(.system(size: 16))
                    .foregroundStyle(usageLevelColor)
                
                Text("Context Window")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Usage stats
            if let usage = usage {
                VStack(alignment: .leading, spacing: 12) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.textTertiary.opacity(0.2))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(usageLevelColor)
                                .frame(width: geo.size.width * CGFloat(min(percentage, 1.0)), height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    // Stats grid
                    VStack(alignment: .leading, spacing: 8) {
                        StatRow(label: "Used", value: formattedTokens(usage.estimatedTokens), highlight: true)
                        
                        if let actual = usage.actualTokens {
                            StatRow(label: "Actual (API)", value: formattedTokens(actual), highlight: false)
                                .foregroundStyle(theme.textSecondary)
                        }
                        
                        StatRow(label: "Context Limit", value: formattedTokens(usage.contextWindow), highlight: false)
                        
                        StatRow(label: "Remaining", value: formattedTokens(usage.remainingTokens), highlight: usage.remainingTokens < 10000)
                    }
                    
                    // Status message
                    HStack(spacing: 6) {
                        Image(systemName: usageLevel.systemColor)
                            .font(.system(size: 12))
                        Text(usageLevel.description)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(usageLevelColor)
                    .padding(.top, 4)
                    
                    if isSending {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Calculating...")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    // Warning for high usage
                    if usage.isNearLimit {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            Text("Consider starting a new chat soon to avoid hitting the context limit.")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)
                    }
                }
            } else {
                // No usage data yet
                VStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.textTertiary)
                    Text("No usage data yet")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                    Text("Send a message to see context usage")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            }
        }
        .padding(16)
        .background(theme.background)
    }
    
    private var usageLevelColor: Color {
        switch usageLevel {
        case .normal: return theme.accent
        case .warning: return .yellow
        case .caution: return .orange
        case .danger: return .red
        }
    }
    
    private func formattedTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

/// A single row in the stats display.
struct StatRow: View {
    let label: String
    let value: String
    let highlight: Bool
    
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: highlight ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(highlight ? theme.textPrimary : theme.textSecondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Normal usage
        ContextUsageIndicator(
            usage: ThreadTokenUsage(
                estimatedTokens: 4500,
                contextWindow: 128000
            ),
            isSending: false
        )
        
        // Warning usage
        ContextUsageIndicator(
            usage: ThreadTokenUsage(
                estimatedTokens: 70000,
                contextWindow: 128000
            ),
            isSending: false
        )
        
        // Danger usage
        ContextUsageIndicator(
            usage: ThreadTokenUsage(
                estimatedTokens: 120000,
                actualTokens: 115000,
                contextWindow: 128000
            ),
            isSending: true
        )
        
        // No data
        ContextUsageIndicator(usage: nil, isSending: false)
    }
    .padding()
}
