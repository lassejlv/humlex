//
//  DebugPerformanceBanner.swift
//  AI Chat
//
//  Created by Codex on 12/02/2026.
//

import Foundation
import SwiftUI

struct DebugPerformanceBanner: View {
    @ObservedObject var monitor: DebugPerformanceMonitor
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            valuePill(title: "FPS", value: "\(monitor.fps)", color: fpsColor)
            valuePill(title: "CPU", value: String(format: "%.1f%%", monitor.cpuPercent), color: cpuColor)
            valuePill(title: "MEM", value: String(format: "%.0f MB", monitor.memoryMB), color: memoryColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surfaceBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.chipBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
        .allowsHitTesting(false)
    }

    private var fpsColor: Color {
        if monitor.fps >= 50 { return .green }
        if monitor.fps >= 30 { return .orange }
        return .red
    }

    private var cpuColor: Color {
        if monitor.cpuPercent < 45 { return .green }
        if monitor.cpuPercent < 80 { return .orange }
        return .red
    }

    private var memoryColor: Color {
        if monitor.memoryMB < 800 { return .green }
        if monitor.memoryMB < 1_500 { return .orange }
        return .red
    }

    private func valuePill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.codeBackground.opacity(0.65), in: Capsule())
        .overlay(Capsule().stroke(theme.codeBorder, lineWidth: 1))
    }
}
