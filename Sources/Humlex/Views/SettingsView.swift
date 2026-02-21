import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case providers = "Providers"
    case mcp = "MCP Servers"
    case theme = "Theme"
    case systemInstructions = "System Instructions"
    case experimental = "Experimental"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "bolt.horizontal"
        case .mcp: return "server.rack"
        case .theme: return "paintbrush"
        case .systemInstructions: return "text.bubble"
        case .experimental: return "flask"
        }
    }
}

struct SettingsView: View {
    @Binding var openAIAPIKey: String
    @Binding var openAICompatibleProfiles: [OpenAICompatibleProfile]
    @Binding var openAICompatibleTokens: [String: String]
    @Binding var anthropicAPIKey: String
    @Binding var openRouterAPIKey: String
    @Binding var fastRouterAPIKey: String
    @Binding var vercelAIAPIKey: String
    @Binding var geminiAPIKey: String
    @Binding var kimiAPIKey: String
    let canMigrateLegacyKeys: Bool

    let isLoadingModels: Bool
    let modelCounts: [AIProvider: Int]
    let statusMessage: String?
    let currentWorkingDirectory: String?
    let onFetchModels: () -> Void
    let onMigrateLegacyKeysToKeychain: () -> Void
    let onImportChats: () -> Void
    let onExportAllChats: () -> Void
    let onDeleteAllChats: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appUpdater: AppUpdater
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var mcpManager = MCPManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var selectedProvider: AIProvider = .openAI
    @AppStorage("provider_ollama_enabled") private var isOllamaEnabled = true
    @AppStorage("auto_scroll_enabled") private var isAutoScrollEnabled = true
    @AppStorage("performance_mode_enabled") private var isPerformanceModeEnabled = true
    @AppStorage("performance_visible_message_limit") private var performanceVisibleMessageLimit =
        250
    @AppStorage("debug_mode_enabled") private var isDebugModeEnabled = false
    @AppStorage("default_system_instructions") private var defaultSystemInstructions: String = ""
    @AppStorage("chat_font_size") private var chatFontSize = 13.0

    // MCP add server form
    @State private var showAddServerForm = false
    @State private var newServerName = ""
    @State private var newServerCommand = ""
    @State private var newServerArgs = ""
    @State private var newServerEnv = ""
    @State private var serverToDelete: String? = nil
    @State private var isShowingDeleteAllChatsAlert = false
    @State private var settingsSearchText: String = ""
    @State private var themeImportStatusMessage: String?
    @State private var isThemeImportError = false

    private var activeSectionTitle: String {
        switch selectedTab {
        case .providers:
            return "Providers"
        case .mcp:
            return "MCP Servers"
        case .general:
            return "General"
        case .theme:
            return "Theme"
        case .systemInstructions:
            return "System Instructions"
        case .experimental:
            return "Experimental"
        }
    }

    private var activeSectionSubtitle: String {
        switch selectedTab {
        case .providers:
            return "Manage API keys and model access"
        case .mcp:
            return "Configure Model Context Protocol servers"
        case .general:
            return "App behavior and defaults"
        case .theme:
            return "Appearance and syntax palette"
        case .systemInstructions:
            return "Default instructions for new chats"
        case .experimental:
            return "Preview features that may change or be removed"
        }
    }

    private var activeSectionIcon: String {
        switch selectedTab {
        case .providers:
            return "bolt.horizontal"
        case .mcp:
            return "server.rack"
        case .general:
            return "gearshape"
        case .theme:
            return "paintbrush"
        case .systemInstructions:
            return "text.bubble"
        case .experimental:
            return "flask"
        }
    }

    private var settingsSearchQuery: String {
        settingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchingSettings: Bool {
        !settingsSearchQuery.isEmpty
    }

    private func matchesSettingsSearch(_ text: String) -> Bool {
        guard isSearchingSettings else { return true }
        return text.localizedCaseInsensitiveContains(settingsSearchQuery)
    }

    private var settingsWindowTop: Color {
        theme.background
    }

    private var settingsWindowBottom: Color {
        theme.background
    }

    private var settingsChromeBackground: Color {
        theme.surfaceBackground
    }

    private var settingsSidebarColor: Color {
        theme.sidebarBackground
    }

    private var settingsCardBackground: Color {
        theme.surfaceBackground.opacity(colorScheme == .dark ? 0.9 : 0.98)
    }

    private var settingsControlBackground: Color {
        theme.background.opacity(colorScheme == .dark ? 0.35 : 0.55)
    }

    private var settingsSelectionBackground: Color {
        theme.accent.opacity(colorScheme == .dark ? 0.2 : 0.12)
    }

    private var settingsBorderColor: Color {
        theme.divider.opacity(0.9)
    }

    private var settingsHoverBackground: Color {
        theme.hoverBackground
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            settingsBorderColor.opacity(0.8).frame(width: 1)

            VStack(spacing: 0) {
                settingsHeader
                settingsBorderColor.opacity(0.8).frame(height: 1)

                settingsDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(settingsChromeBackground)

                settingsBorderColor.opacity(0.8).frame(height: 1)
                bottomBar
            }
        }
        .frame(width: 980, height: 700)
        .background(settingsWindowTop)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(settingsBorderColor.opacity(0.8), lineWidth: 1)
        )
        .alert("Delete All Chats", isPresented: $isShowingDeleteAllChatsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                onDeleteAllChats()
            }
        } message: {
            Text("This removes all conversations and cannot be undone.")
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: activeSectionIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(activeSectionTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(activeSectionSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Spacer()

            if selectedTab == .providers {
                statusBadge
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(settingsChromeBackground)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch selectedTab {
        case .general:
            generalDetail
        case .providers:
            providerOverviewDetail
        case .mcp:
            mcpDetail
        case .theme:
            themeDetail
        case .systemInstructions:
            systemInstructionsDetail
        case .experimental:
            experimentalDetail
        }
    }

    // MARK: - Settings Sidebar

    private var settingsSidebar: some View {
        let generalTabs: [SettingsTab] = [.general, .theme, .systemInstructions, .experimental]
        let aiTabs: [SettingsTab] = [.providers]
        let filteredGeneralTabs = generalTabs.filter { matchesSettingsSearch($0.rawValue) }
        let filteredAITabs = aiTabs.filter { matchesSettingsSearch($0.rawValue) }
        let showIntegrations = matchesSettingsSearch(SettingsTab.mcp.rawValue)
        let hasAnySidebarResult =
            !filteredGeneralTabs.isEmpty
            || !filteredAITabs.isEmpty
            || showIntegrations

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TextField("Search settings", text: $settingsSearchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))

                if !filteredGeneralTabs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarSectionTitle("General")
                        ForEach(filteredGeneralTabs) { tab in
                            sidebarTabButton(tab)
                        }
                    }
                }

                if !filteredAITabs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarSectionTitle("AI")
                        ForEach(filteredAITabs) { tab in
                            sidebarTabButton(tab)
                        }
                    }
                }

                if showIntegrations {
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarSectionTitle("Integrations")
                        sidebarTabButton(.mcp)
                    }
                }

                if isSearchingSettings && !hasAnySidebarResult {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No matches")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        Text("Try a section name.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .frame(width: 270)
        .background(settingsSidebarColor)
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    private func sidebarTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
            if let first = providers(for: tab).first {
                selectedProvider = first
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .frame(width: 18)

                Text(tab.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? settingsSelectionBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider Detail

    private var providerOverviewDetail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Provider overview")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(providers(for: selectedTab)) { provider in
                            providerOverviewChip(provider, in: selectedTab)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            settingsBorderColor.opacity(0.7).frame(height: 1)

            providerDetail
        }
    }

    private func providerOverviewChip(_ provider: AIProvider, in tab: SettingsTab) -> some View {
        let isSelected = selectedProvider == provider && selectedTab == tab
        let hasKey = providerHasRequiredCredentials(provider)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProvider = provider
            }
        } label: {
            HStack(spacing: 8) {
                ProviderIcon(slug: provider.iconSlug, size: 15)
                    .foregroundColor(isSelected ? theme.accent : theme.textSecondary)

                Text(provider.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

                Circle()
                    .fill(hasKey ? Color.green.opacity(0.85) : theme.textTertiary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? settingsSelectionBackground : settingsControlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? theme.accent.opacity(0.35) : settingsBorderColor.opacity(0.7),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

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
                if selectedProvider == .ollama {
                    ollamaDetailView
                } else if selectedProvider == .openAICompatible {
                    openAICompatibleDetailView
                } else {
                    apiKeyField
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedTab) { _, newValue in
            let available = providers(for: newValue)
            if let first = available.first, !available.contains(selectedProvider) {
                selectedProvider = first
            }
        }
    }

    private var ollamaDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Enabled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Toggle("", isOn: $isOllamaEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.accent)
            }

            Text("Local Endpoint")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            Text("http://localhost:11434")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.codeBorder, lineWidth: 1)
                )

            Text(
                "Ollama runs locally and does not require an API key. Models are fetched from your local Ollama server."
            )
            .font(.system(size: 12))
            .foregroundStyle(theme.textSecondary)
        }
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
                        settingsControlBackground,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(settingsBorderColor, lineWidth: 1)
                    )
            }
        }
    }

    private var openAICompatibleDetailView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Profiles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Button {
                    openAICompatibleProfiles.append(
                        OpenAICompatibleProfile(
                            name: "OpenAI Compatible \(openAICompatibleProfiles.count + 1)",
                            baseURL: ""
                        )
                    )
                } label: {
                    Label("Add Profile", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if openAICompatibleProfiles.isEmpty {
                Text("No profiles yet. Add one with a custom name, endpoint, and bearer token.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }

            ForEach(Array(openAICompatibleProfiles.indices), id: \.self) { idx in
                let profileID = openAICompatibleProfiles[idx].id
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Profile \(idx + 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Button(role: .destructive) {
                            openAICompatibleTokens[profileID] = nil
                            openAICompatibleProfiles.remove(at: idx)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Remove profile")
                    }

                    TextField(
                        "Custom name (e.g. My Local Server)",
                        text: Binding(
                            get: { openAICompatibleProfiles[idx].name },
                            set: { openAICompatibleProfiles[idx].name = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "https://your-host.example.com/v1",
                        text: Binding(
                            get: { openAICompatibleProfiles[idx].baseURL },
                            set: { openAICompatibleProfiles[idx].baseURL = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    SecureField(
                        "Bearer token",
                        text: Binding(
                            get: { openAICompatibleTokens[profileID] ?? "" },
                            set: { openAICompatibleTokens[profileID] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                .background(
                    settingsCardBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(settingsBorderColor, lineWidth: 1)
                )
            }

            Text("Supports OpenAI-style APIs. If `/v1` is omitted, it is added automatically.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let count = modelCounts[selectedProvider] ?? 0
        let hasKey: Bool = {
            providerHasRequiredCredentials(selectedProvider)
        }()

        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                Text("\(count) models")
                    .font(.system(size: 11))
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
                    .font(.system(size: 11))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(settingsControlBackground, in: Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "circle")
                    .font(.system(size: 11))
                Text("No key")
                    .font(.system(size: 11))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(settingsControlBackground, in: Capsule())
        }
    }

    // MARK: - MCP Detail

    private var mcpDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("MCP Servers")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                if mcpManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                mcpToolCountBadge

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddServerForm.toggle()
                    }
                } label: {
                    Image(systemName: showAddServerForm ? "xmark" : "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            settingsControlBackground,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(showAddServerForm ? "Cancel" : "Add server")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Add server form
                    if showAddServerForm {
                        mcpAddServerForm
                    }

                    // Config file path
                    mcpConfigPathSection

                    settingsBorderColor.opacity(0.7).frame(height: 1)

                    // Server list
                    let serverNames = Array(mcpManager.serverStatuses.keys).sorted()
                    if serverNames.isEmpty && !showAddServerForm {
                        mcpEmptyState
                    } else {
                        ForEach(serverNames, id: \.self) { name in
                            mcpServerCard(name)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .alert(
            "Remove Server",
            isPresented: Binding<Bool>(
                get: { serverToDelete != nil },
                set: { if !$0 { serverToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                serverToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let name = serverToDelete {
                    Task {
                        await mcpManager.removeServer(name: name)
                    }
                }
                serverToDelete = nil
            }
        } message: {
            Text(
                "Are you sure you want to remove \"\(serverToDelete ?? "")\"? This will update your mcp.json config file."
            )
        }
    }

    private var mcpToolCountBadge: some View {
        let count = mcpManager.tools.count
        return HStack(spacing: 4) {
            Image(systemName: count > 0 ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                .font(.system(size: 11))
            Text("\(count) tool\(count == 1 ? "" : "s")")
                .font(.system(size: 11))
        }
        .foregroundColor(count > 0 ? .green : theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (count > 0 ? Color.green.opacity(0.12) : settingsControlBackground),
            in: Capsule()
        )
    }

    private var mcpAddServerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add MCP Server")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            mcpFormField(label: "Name", placeholder: "e.g. filesystem", text: $newServerName)
            mcpFormField(label: "Command", placeholder: "e.g. npx", text: $newServerCommand)
            mcpFormField(
                label: "Arguments",
                placeholder: "e.g. -y @modelcontextprotocol/server-filesystem /path",
                text: $newServerArgs)
            mcpFormField(
                label: "Environment", placeholder: "e.g. API_KEY=abc123 OTHER=value",
                text: $newServerEnv)

            HStack {
                Spacer()

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        resetAddServerForm()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .font(.system(size: 12, weight: .medium))

                Button {
                    Task {
                        await addServer()
                    }
                } label: {
                    Text("Add Server")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(
                    newServerName.trimmingCharacters(in: .whitespaces).isEmpty
                        || newServerCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(
            settingsCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(settingsBorderColor, lineWidth: 1)
        )
    }

    private func mcpFormField(label: String, placeholder: String, text: Binding<String>)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    theme.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.codeBorder, lineWidth: 1)
                )
        }
    }

    private func addServer() async {
        let name = newServerName.trimmingCharacters(in: .whitespaces)
        let command = newServerCommand.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !command.isEmpty else { return }

        // Parse args: split by spaces, respecting simple quoting
        let args = parseArgs(newServerArgs)

        // Parse env: "KEY=value KEY2=value2"
        let env = parseEnv(newServerEnv)

        await mcpManager.addServer(
            name: name, command: command, args: args, env: env.isEmpty ? nil : env)

        withAnimation(.easeInOut(duration: 0.2)) {
            resetAddServerForm()
        }
    }

    private func resetAddServerForm() {
        showAddServerForm = false
        newServerName = ""
        newServerCommand = ""
        newServerArgs = ""
        newServerEnv = ""
    }

    private func parseArgs(_ input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        // Simple split — handles space-separated args
        // For quoted strings, do a basic parse
        var args: [String] = []
        var current = ""
        var inQuote: Character? = nil
        for ch in trimmed {
            if let q = inQuote {
                if ch == q {
                    inQuote = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == " " {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { args.append(current) }
        return args
    }

    private func parseEnv(_ input: String) -> [String: String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [:] }
        var env: [String: String] = [:]
        // Split by spaces, then by first '='
        for pair in trimmed.components(separatedBy: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                env[String(parts[0])] = String(parts[1])
            }
        }
        return env
    }

    private var mcpConfigPathSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Config File")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 8) {
                let configPath = "~/Library/Application Support/Humlex/mcp.json"
                Text(configPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    // Open the config directory in Finder
                    let appSupport = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first!
                    let appDir = appSupport.appendingPathComponent("Humlex")
                    // Create directory if it doesn't exist
                    try? FileManager.default.createDirectory(
                        at: appDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(appDir)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Open config directory in Finder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.codeBorder, lineWidth: 1)
            )
        }
    }

    private var mcpEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 24))
                .foregroundStyle(theme.textTertiary)

            Text("No MCP servers configured")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            Text("Add servers to mcp.json to get started")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func mcpServerCard(_ name: String) -> some View {
        let status = mcpManager.serverStatuses[name] ?? .disconnected
        let serverTools = mcpManager.tools.filter { $0.serverName == name }

        return VStack(alignment: .leading, spacing: 10) {
            // Server name and status
            HStack {
                Circle()
                    .fill(mcpStatusColor(status))
                    .frame(width: 8, height: 8)

                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Text(status.label)
                    .font(.system(size: 11))
                    .foregroundStyle(mcpStatusTextColor(status))

                // Reconnect button
                Button {
                    Task {
                        await mcpManager.reconnect(serverName: name)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Reconnect server")

                // Delete button
                Button {
                    serverToDelete = name
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Remove server")
            }

            // Tools list
            if !serverTools.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tools (\(serverTools.count))")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 6)],
                        alignment: .leading, spacing: 6
                    ) {
                        ForEach(serverTools) { tool in
                            mcpToolChip(tool)
                        }
                    }
                }
            } else if status == .connected {
                Text("No tools discovered")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(12)
        .background(
            settingsControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(settingsBorderColor, lineWidth: 1)
        )
    }

    private func mcpToolChip(_ tool: MCPTool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wrench.fill")
                .font(.system(size: 9))
            Text(tool.name)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(settingsControlBackground, in: Capsule())
        .overlay(Capsule().stroke(settingsBorderColor, lineWidth: 0.5))
        .help(tool.description)
    }

    private func mcpStatusColor(_ status: MCPManager.ServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private func mcpStatusTextColor(_ status: MCPManager.ServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return theme.textTertiary
        }
    }

    // MARK: - Theme Detail

    private var themeDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Theme")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button {
                    importThemeFromJSON()
                } label: {
                    Label("Import JSON", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            Text("Import a custom theme from JSON with id/name/prefersDarkAppearance/colors.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            if let themeImportStatusMessage {
                Text(themeImportStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isThemeImportError ? Color.red : Color.green)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(themeManager.themes) { t in
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
                    .fill(isSelected ? settingsSelectionBackground : settingsControlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? theme.accent.opacity(0.4) : settingsBorderColor, lineWidth: 1)
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

    private func importThemeFromJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import Theme"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let importedCount = try themeManager.importThemes(from: url)
            themeImportStatusMessage =
                "Imported \(importedCount) theme\(importedCount == 1 ? "" : "s") from \(url.lastPathComponent)."
            isThemeImportError = false
        } catch {
            themeImportStatusMessage = error.localizedDescription
            isThemeImportError = true
        }
    }

    // MARK: - System Instructions Detail

    private var systemInstructionsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("System Instructions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                if !defaultSystemInstructions.isEmpty {
                    Button {
                        defaultSystemInstructions = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear system instructions")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "These instructions will be used as the default system prompt for all new chats. They define how the AI should behave and respond."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Text editor
            TextEditor(text: $defaultSystemInstructions)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .background(theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.codeBorder, lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(settingsChromeBackground)
    }

    // MARK: - Experimental Detail

    private var experimentalDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Warning banner
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Experimental Features")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(
                                "These features are under development and may be unstable, change, or be removed in future versions."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.orange.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )

                    if ExperimentalFeatures.allFeatures.isEmpty {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "flask")
                                .font(.system(size: 32))
                                .foregroundStyle(theme.textTertiary)

                            Text("No experimental features available")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.textSecondary)

                            Text("Check back later for new features to try out.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        settingsGroup("Features") {
                            VStack(spacing: 0) {
                                ForEach(
                                    Array(ExperimentalFeatures.allFeatures.enumerated()),
                                    id: \.element.id
                                ) { index, flag in
                                    experimentalFeatureRow(flag: flag)

                                    if index < ExperimentalFeatures.allFeatures.count - 1 {
                                        settingsBorderColor.opacity(0.6).frame(height: 1)
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func experimentalFeatureRow(flag: ExperimentalFeatures.Flag) -> some View {
        let info = ExperimentalFeatures.info(for: flag)
        let isEnabled = Binding(
            get: { ExperimentalFeatures.isEnabled(flag) },
            set: { ExperimentalFeatures.setEnabled(flag, enabled: $0) }
        )

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(info.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.textPrimary)

                        if info.requiresRestart {
                            Text("Restart required")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Color.orange.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(info.description)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - General Detail

    private var generalDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsGroup("Appearance") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Chat font size")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Text("\(Int(chatFontSize.rounded())) pt")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(settingsControlBackground, in: Capsule())
                            }

                            Slider(value: $chatFontSize, in: 11...20, step: 1)
                                .tint(theme.accent)

                            Text("Preview: The quick brown fox jumps over the lazy dog.")
                                .font(.system(size: chatFontSize))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }

                    settingsGroup("Behavior") {
                        settingsToggleRow(
                            title: "Auto-scroll",
                            subtitle:
                                "Automatically scroll to new messages during streaming.",
                            isOn: $isAutoScrollEnabled,
                            showDivider: true
                        )
                        settingsToggleRow(
                            title: "Performance mode",
                            subtitle:
                                "Render recent messages first and load older messages on demand.",
                            isOn: $isPerformanceModeEnabled,
                            showDivider: true
                        )
                        settingsToggleRow(
                            title: "Debug mode",
                            subtitle: "Show FPS, CPU, and memory metrics overlay.",
                            isOn: $isDebugModeEnabled,
                            showDivider: false
                        )
                    }

                    settingsGroup("Performance") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Messages to keep visible")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Text("\(performanceVisibleMessageLimit)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(settingsControlBackground, in: Capsule())
                            }

                            Picker(
                                "Messages to keep visible",
                                selection: $performanceVisibleMessageLimit
                            ) {
                                Text("100").tag(100)
                                Text("250").tag(250)
                                Text("500").tag(500)
                                Text("1000").tag(1000)
                            }
                            .pickerStyle(.segmented)
                            .disabled(!isPerformanceModeEnabled)

                            if !isPerformanceModeEnabled {
                                Text("Enable Performance mode to apply this setting.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }

                    settingsGroup("Chat Data") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Import from zip/json, export all chats to zip, or delete all chats."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)

                            HStack(spacing: 8) {
                                Button {
                                    onImportChats()
                                } label: {
                                    Label("Import", systemImage: "square.and.arrow.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accent)

                                Button {
                                    onExportAllChats()
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    isShowingDeleteAllChatsAlert = true
                                } label: {
                                    Label("Delete All", systemImage: "trash")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                settingsCardBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(settingsBorderColor.opacity(0.75), lineWidth: 1)
            )
        }
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String?,
        isOn: Binding<Bool>,
        showDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showDivider {
                settingsBorderColor
                    .opacity(0.6)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
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
                if canMigrateLegacyKeys {
                    Button {
                        onMigrateLegacyKeysToKeychain()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.horizontal")
                            Text("Migrate Legacy Keys")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    onFetchModels()
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: "arrow.down.circle")
                        Text("Fetch Models")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingModels)
            }

            if selectedTab == .mcp {
                Button {
                    Task {
                        await mcpManager.loadAndConnect()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if mcpManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text("Reload All")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(mcpManager.isLoading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(settingsChromeBackground)
    }

    // MARK: - Helpers

    private func apiKeyBinding(for provider: AIProvider) -> Binding<String> {
        switch provider {
        case .openAI: return $openAIAPIKey
        case .openAICompatible: return .constant("")
        case .anthropic: return $anthropicAPIKey
        case .openRouter: return $openRouterAPIKey
        case .fastRouter: return $fastRouterAPIKey
        case .vercelAI: return $vercelAIAPIKey
        case .gemini: return $geminiAPIKey
        case .kimi: return $kimiAPIKey
        case .ollama: return .constant("")  // Ollama uses local server, no API key
        }
    }

    private func providerHasRequiredCredentials(_ provider: AIProvider) -> Bool {
        if !provider.requiresAPIKey {
            return true
        }

        let hasKey = !apiKeyBinding(for: provider).wrappedValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty

        if provider == .openAICompatible {
            return openAICompatibleProfiles.contains { profile in
                let hasEndpoint = !profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                let hasToken =
                    !(openAICompatibleTokens[profile.id] ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                return hasEndpoint && hasToken
            }
        }

        return hasKey
    }

    private func providers(for tab: SettingsTab) -> [AIProvider] {
        switch tab {
        case .general, .mcp, .theme, .systemInstructions, .experimental:
            return []
        case .providers:
            return AIProvider.allCases
        }
    }

}
