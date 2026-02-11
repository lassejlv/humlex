//
//  MCPServerDropdown.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import SwiftUI

struct MCPServerDropdown: View {
    @Binding var isPresented: Bool
    @ObservedObject var mcpManager = MCPManager.shared

    @Environment(\.appTheme) private var theme

    private var hasServers: Bool {
        !mcpManager.serverStatuses.isEmpty
    }

    private var connectedCount: Int {
        mcpManager.serverStatuses.values.filter { status in
            if case .connected = status { return true }
            return false
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            theme.divider.frame(height: 1)
            serverList
        }
        .frame(width: 280, height: min(CGFloat(mcpManager.serverStatuses.count * 44 + 60), 320))
        .background(theme.surfaceBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)

            Text("MCP Servers")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            if hasServers {
                Text("\(connectedCount)/\(mcpManager.serverStatuses.count) connected")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !hasServers {
                    emptyState
                } else {
                    ForEach(Array(mcpManager.serverStatuses.keys.sorted()), id: \.self) { serverName in
                        if let status = mcpManager.serverStatuses[serverName] {
                            serverRow(name: serverName, status: status)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 24))
                .foregroundStyle(theme.textTertiary)
            Text("No MCP servers configured")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Text("Add servers in Settings → MCP")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func serverRow(name: String, status: MCPManager.ServerStatus) -> some View {
        HStack(spacing: 10) {
            statusIndicator(status)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Text(statusLabel(status))
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor(status).opacity(0.8))
            }

            Spacer()

            if case .error = status {
                Button {
                    Task {
                        await mcpManager.reconnect(serverName: name)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help("Reconnect server")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func statusIndicator(_ status: MCPManager.ServerStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(statusColor(status).opacity(0.3), lineWidth: 2)
            )
    }

    private func statusColor(_ status: MCPManager.ServerStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }

    private func statusLabel(_ status: MCPManager.ServerStatus) -> String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .error(let msg):
            return msg.count > 30 ? String(msg.prefix(30)) + "..." : msg
        case .disconnected:
            return "Disconnected"
        }
    }
}
