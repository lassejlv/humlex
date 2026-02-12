//
//  AppStatusBarView.swift
//  AI Chat
//
//  Created by Codex on 12/02/2026.
//

import Foundation
import SwiftUI

struct AppStatusBarView: View {
    let status: StatusUpdateSDK.StatusItem?
    let fallbackText: String?

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)

            Text(displayText)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)

            Spacer()

            if let source = status?.source {
                Text(source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.chipBackground, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.surfaceBackground.opacity(0.75))
        .overlay(
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var displayText: String {
        if let status {
            return status.message
        }
        if let fallbackText, !fallbackText.isEmpty {
            return fallbackText
        }
        return "Ready"
    }

    private var indicatorColor: Color {
        guard let status else { return theme.textTertiary.opacity(0.7) }
        switch status.level {
        case .info: return theme.accent
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
