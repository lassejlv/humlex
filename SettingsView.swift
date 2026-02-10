import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case providers = "Providers"
    case theme = "Theme"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .providers: return "bolt.horizontal"
        case .theme: return "paintbrush"
        }
    }
}

struct SettingsView: View {
    @Binding var openAIAPIKey: String
    @Binding var anthropicAPIKey: String
    @Binding var openRouterAPIKey: String
    @Binding var vercelAIAPIKey: String
    @Binding var geminiAPIKey: String

    let isLoadingModels: Bool
    let modelCounts: [AIProvider: Int]
    let statusMessage: String?
    let onFetchModels: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.appTheme) private var theme

    @State private var selectedTab: SettingsTab = .providers
    @State private var selectedProvider: AIProvider = .openAI

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            theme.divider.frame(height: 1)

            // Main content: sidebar + detail
            HStack(spacing: 0) {
                settingsSidebar
                theme.divider.frame(width: 1)

                switch selectedTab {
                case .providers:
                    providerDetail
                case .theme:
                    themeDetail
                }
            }

            theme.divider.frame(height: 1)

            // Bottom bar
            bottomBar
        }
        .frame(width: 640, height: 480)
        .background(theme.background)
    }

    // MARK: - Settings Sidebar

    private var settingsSidebar: some View {
        ScrollView {
            VStack(spacing: 2) {
                // Tab buttons
                ForEach(SettingsTab.allCases) { tab in
                    tabRow(tab)
                }

                // Provider sub-items (shown when providers tab is selected)
                if selectedTab == .providers {
                    theme.divider.frame(height: 1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)

                    ForEach(AIProvider.allCases) { provider in
                        providerRow(provider)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 200)
        .background(theme.sidebarBackground)
    }

    private func tabRow(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .frame(width: 18)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(theme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? theme.selectionBackground
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        let isSelected = selectedTab == .providers && selectedProvider == provider
        let hasKey = !apiKeyBinding(for: provider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Button {
            selectedTab = .providers
            selectedProvider = provider
        } label: {
            HStack(spacing: 10) {
                ProviderIcon(slug: provider.iconSlug, size: 18)
                    .foregroundColor(isSelected ? theme.accent : theme.textSecondary)

                Text(provider.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                if hasKey {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(theme.textTertiary.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? theme.selectionBackground
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider Detail

    private var providerDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(selectedProvider.rawValue)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Fields
            VStack(alignment: .leading, spacing: 20) {
                apiKeyField
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 8) {
                SecureField("Enter API key...", text: apiKeyBinding(for: selectedProvider))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        theme.surfaceBackground,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.composerBorder, lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let count = modelCounts[selectedProvider] ?? 0
        let hasKey = !apiKeyBinding(for: selectedProvider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                Text("\(count) models")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12), in: Capsule())
        } else if hasKey {
            HStack(spacing: 4) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 11))
                Text("Not loaded")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.chipBackground, in: Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "circle")
                    .font(.system(size: 11))
                Text("No key")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.chipBackground, in: Capsule())
        }
    }

    // MARK: - Theme Detail

    private var themeDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Theme")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(AppTheme.allThemes) { t in
                        themeCard(t)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func themeCard(_ t: AppTheme) -> some View {
        let isSelected = themeManager.current.id == t.id
        return Button {
            themeManager.select(t)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(theme.accent)
                            .font(.system(size: 14))
                    }
                }

                // Color preview strip
                HStack(spacing: 4) {
                    colorSwatch(t.syntaxKeyword)
                    colorSwatch(t.syntaxString)
                    colorSwatch(t.syntaxFunction)
                    colorSwatch(t.syntaxType)
                    colorSwatch(t.syntaxNumber)
                    colorSwatch(t.syntaxComment)

                    // Small preview of background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(t.background)
                        .frame(width: 20, height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(t.codeBorder, lineWidth: 0.5)
                        )

                    Spacer()
                }

                // Code preview
                codePreview(forTheme: t)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.selectionBackground : theme.hoverBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.4) : theme.chipBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 20, height: 10)
    }

    private func codePreview(forTheme t: AppTheme) -> some View {
        let previewCode = "func hello() -> String {"
        let highlighted = SyntaxHighlighter.highlight(previewCode, language: "swift", theme: t)
        return Text(highlighted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.codeBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(t.codeBorder, lineWidth: 1)
            )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if selectedTab == .providers {
                Button {
                    onFetchModels()
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Fetch Models")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .disabled(isLoadingModels)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func apiKeyBinding(for provider: AIProvider) -> Binding<String> {
        switch provider {
        case .openAI: return $openAIAPIKey
        case .anthropic: return $anthropicAPIKey
        case .openRouter: return $openRouterAPIKey
        case .vercelAI: return $vercelAIAPIKey
        case .gemini: return $geminiAPIKey
        }
    }
}
