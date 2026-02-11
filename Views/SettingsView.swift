import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case providers = "Providers"
    case experimental = "Experimental"
    case mcp = "MCP Servers"
    case theme = "Theme"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "bolt.horizontal"
        case .experimental: return "flask"
        case .mcp: return "server.rack"
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
    @Binding var kimiAPIKey: String

    let isLoadingModels: Bool
    let modelCounts: [AIProvider: Int]
    let statusMessage: String?
    let onFetchModels: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appUpdater: AppUpdater
    @Environment(\.appTheme) private var theme
    @ObservedObject private var mcpManager = MCPManager.shared

    @State private var selectedTab: SettingsTab = .providers
    @State private var selectedProvider: AIProvider = .openAI
    @State private var claudeCodeAvailability: ClaudeCodeAvailability?
    @State private var codexAvailability: CodexAvailability?
    @State private var isLoggingIntoCodex = false
    @AppStorage("experimental_claude_code_enabled") private var isClaudeCodeEnabled = false
    @AppStorage("experimental_codex_enabled") private var isCodexEnabled = false
    @AppStorage("codex_sandbox_mode") private var codexSandboxModeRaw: String = CodexSandboxMode
        .readOnly.rawValue
    @AppStorage("auto_scroll_enabled") private var isAutoScrollEnabled = true

    // MCP add server form
    @State private var showAddServerForm = false
    @State private var newServerName = ""
    @State private var newServerCommand = ""
    @State private var newServerArgs = ""
    @State private var newServerEnv = ""
    @State private var serverToDelete: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Modern title bar with centered title
            ZStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(
                                theme.hoverBackground,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.background)

            theme.divider.frame(height: 1)

            // Main content: sidebar + detail
            HStack(spacing: 0) {
                settingsSidebar
                theme.divider.frame(width: 1)

                switch selectedTab {
                case .general:
                    generalDetail
                case .providers:
                    providerDetail
                case .experimental:
                    providerDetail
                case .mcp:
                    mcpDetail
                case .theme:
                    themeDetail
                }
            }

            theme.divider.frame(height: 1)

            // Bottom bar
            bottomBar
        }
        .frame(width: 700, height: 520)
        .background(theme.background)
    }

    // MARK: - Settings Sidebar

    private var settingsSidebar: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Main navigation section
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        tabRow(tab)
                    }
                }

                // Provider sub-items (shown when providers tab is selected)
                if selectedTab == .providers {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Providers")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 12)
                        
                        VStack(spacing: 1) {
                            ForEach(providers(for: .providers)) { provider in
                                providerRow(provider)
                            }
                        }
                    }
                }

                // Experimental provider sub-items
                if selectedTab == .experimental {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Experimental")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 12)
                        
                        VStack(spacing: 1) {
                            ForEach(providers(for: .experimental)) { provider in
                                experimentalProviderRow(provider)
                            }
                        }
                    }
                }

                // MCP server sub-items (shown when MCP tab is selected)
                if selectedTab == .mcp {
                    let serverNames = Array(mcpManager.serverStatuses.keys).sorted()
                    if !serverNames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Servers")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.horizontal, 12)
                            
                            VStack(spacing: 1) {
                                ForEach(serverNames, id: \.self) { name in
                                    mcpServerRow(name)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(width: 220)
        .background(theme.sidebarBackground)
    }

    private func tabRow(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
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
        let isSelected = selectedProvider == provider && selectedTab == settingsTab(for: provider)
        let hasKey: Bool = {
            if !provider.requiresAPIKey {
                return true
            }
            if provider == .claudeCode {
                return claudeCodeAvailability?.isAvailable == true
            }
            if provider == .openAICodex {
                return codexAvailability?.isAvailable == true
            }
            return !apiKeyBinding(for: provider).wrappedValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }()

        return Button {
            selectedTab = settingsTab(for: provider)
            selectedProvider = provider
        } label: {
            HStack(spacing: 10) {
                ProviderIcon(slug: provider.iconSlug, size: 16)
                    .foregroundColor(isSelected ? theme.accent : theme.textSecondary)

                Text(provider.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

                Spacer()

                if hasKey {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? theme.selectionBackground
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func experimentalProviderRow(_ provider: AIProvider) -> some View {
        let isSelected = selectedProvider == provider && selectedTab == .experimental
        let isEnabled = experimentalToggleBinding(for: provider).wrappedValue

        return HStack(spacing: 8) {
            Button {
                selectedTab = .experimental
                selectedProvider = provider
            } label: {
                HStack(spacing: 10) {
                    ProviderIcon(slug: provider.iconSlug, size: 18)
                        .foregroundColor(isSelected ? theme.accent : theme.textSecondary)

                    Text(provider.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(isEnabled ? theme.textPrimary : theme.textTertiary)

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

            Toggle("", isOn: experimentalToggleBinding(for: provider))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.75)
        }
    }

    private func mcpServerRow(_ name: String) -> some View {
        let status = mcpManager.serverStatuses[name] ?? .disconnected
        return HStack(spacing: 10) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18)

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Circle()
                .fill(mcpStatusColor(status))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
                if selectedProvider == .claudeCode {
                    claudeCodeDetailView
                } else if selectedProvider == .openAICodex {
                    codexDetailView
                } else if selectedProvider == .ollama {
                    ollamaDetailView
                } else {
                    apiKeyField
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if selectedProvider == .claudeCode {
                checkClaudeCodeAvailability()
            } else if selectedProvider == .openAICodex {
                checkCodexAvailability()
            }
        }
        .onChange(of: selectedProvider) { _, newValue in
            if newValue == .claudeCode {
                checkClaudeCodeAvailability()
            } else if newValue == .openAICodex {
                checkCodexAvailability()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            let available = providers(for: newValue)
            if let first = available.first, !available.contains(selectedProvider) {
                selectedProvider = first
            }
        }
    }

    // MARK: - Claude Code Detail

    private var ollamaDetailView: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.codeBorder, lineWidth: 1)
                )

            Text("Ollama runs locally and does not require an API key. Models are fetched from your local Ollama server.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Claude Code Detail

    private var claudeCodeDetailView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // CLI Status
            VStack(alignment: .leading, spacing: 8) {
                Text("CLI Status")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                HStack(spacing: 10) {
                    if let availability = claudeCodeAvailability {
                        Circle()
                            .fill(availability.isAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        Text(availability.statusMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking CLI availability...")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer()

                    Button {
                        checkClaudeCodeAvailability()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Re-check CLI availability")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    theme.surfaceBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.composerBorder, lineWidth: 1)
                )
            }

            // Install instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Code authenticates via the CLI itself — no API key needed.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)

                    HStack(spacing: 6) {
                        Text("Install:")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)

                        Text("npm install -g @anthropic-ai/claude-code")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
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
            }
        }
    }

    private func checkClaudeCodeAvailability() {
        claudeCodeAvailability = nil
        Task {
            let result = await ClaudeCodeAvailability.check()
            await MainActor.run {
                claudeCodeAvailability = result
            }
        }
    }

    // MARK: - OpenAI Codex Detail

    private var codexDetailView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // CLI Status
            VStack(alignment: .leading, spacing: 8) {
                Text("CLI Status")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                HStack(spacing: 10) {
                    if let availability = codexAvailability {
                        Circle()
                            .fill(availability.isAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        Text(availability.statusMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking CLI availability...")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer()

                    Button {
                        checkCodexAvailability()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Re-check CLI availability")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    theme.surfaceBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.composerBorder, lineWidth: 1)
                )
            }

            // Authentication
            if let availability = codexAvailability, availability.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)

                    HStack(spacing: 10) {
                        if availability.isLoggedIn {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Logged in via ChatGPT")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textPrimary)
                        } else {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Not logged in")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textPrimary)
                        }

                        Spacer()

                        if !availability.isLoggedIn {
                            Button {
                                loginToCodex()
                            } label: {
                                HStack(spacing: 4) {
                                    if isLoggingIntoCodex {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                    Text(
                                        isLoggingIntoCodex ? "Logging in..." : "Login with ChatGPT"
                                    )
                                    .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isLoggingIntoCodex)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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

            // Sandbox Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Sandbox Mode")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                VStack(spacing: 4) {
                    ForEach(Array(CodexSandboxMode.allCases), id: \.self) {
                        (mode: CodexSandboxMode) in
                        let modeSelected = (codexSandboxModeRaw == mode.rawValue)
                        Button {
                            codexSandboxModeRaw = mode.rawValue
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(
                                        modeSelected ? theme.accent : theme.textSecondary
                                    )
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(
                                            .system(
                                                size: 13,
                                                weight: modeSelected ? .semibold : .regular)
                                        )
                                        .foregroundStyle(theme.textPrimary)

                                    Text(mode.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                }

                                Spacer()

                                if modeSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                modeSelected ? theme.accent.opacity(0.1) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    theme.surfaceBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.composerBorder, lineWidth: 1)
                )
            }

            // Install instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "OpenAI Codex uses your ChatGPT Plus or Pro subscription — no API key needed."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                    HStack(spacing: 6) {
                        Text("Install:")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)

                        Text("npm install -g @openai/codex")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 6) {
                        Text("Or:")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)

                        Text("brew install --cask codex")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
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
            }
        }
    }

    private func checkCodexAvailability() {
        codexAvailability = nil
        Task {
            let result = await CodexAvailability.check()
            await MainActor.run {
                codexAvailability = result
            }
        }
    }

    private func loginToCodex() {
        isLoggingIntoCodex = true
        Task {
            let success = await CodexAvailability.performLogin()
            await MainActor.run {
                isLoggingIntoCodex = false
                if success {
                    // Refresh availability to pick up new login status
                    checkCodexAvailability()
                }
            }
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
        let isEnabled = !isExperimentalProvider(selectedProvider)
            || experimentalToggleBinding(for: selectedProvider).wrappedValue
        let hasKey: Bool = {
            if !selectedProvider.requiresAPIKey {
                return true
            }
            if selectedProvider == .claudeCode {
                return claudeCodeAvailability?.isAvailable == true
            }
            if selectedProvider == .openAICodex {
                return codexAvailability?.isAvailable == true
            }
            return !apiKeyBinding(for: selectedProvider).wrappedValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }()

        if !isEnabled {
            HStack(spacing: 4) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 11))
                Text("Disabled")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.chipBackground, in: Capsule())
        } else if count > 0 {
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
                            theme.chipBackground,
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

                    theme.divider.frame(height: 1)

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
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(count > 0 ? .green : theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (count > 0 ? Color.green.opacity(0.12) : theme.chipBackground),
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
            theme.surfaceBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func mcpFormField(label: String, placeholder: String, text: Binding<String>)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
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
                        .font(.system(size: 11, weight: .medium))
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
            theme.hoverBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.chipBorder, lineWidth: 1)
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
        .background(theme.chipBackground, in: Capsule())
        .overlay(Capsule().stroke(theme.chipBorder, lineWidth: 0.5))
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

    // MARK: - General Detail

    private var generalDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("General")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Auto-scroll setting
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-scroll")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)

                                Text("Automatically scroll to new messages during streaming. When disabled, you'll need to scroll manually.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Toggle("", isOn: $isAutoScrollEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        if isAutoScrollEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)

                                Text("Scrolling up will pause auto-scroll until you scroll back to the bottom")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(.leading, 36)
                        }
                    }
                    .padding(16)
                    .background(
                        theme.surfaceBackground,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.chipBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
                        Text("Reload All")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .disabled(mcpManager.isLoading)
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
        case .kimi: return $kimiAPIKey
        case .ollama: return .constant("")  // Ollama uses local server, no API key
        case .claudeCode: return .constant("")  // Claude Code doesn't use an API key
        case .openAICodex: return .constant("")  // Codex doesn't use an API key
        }
    }

    private func providers(for tab: SettingsTab) -> [AIProvider] {
        switch tab {
        case .general, .mcp, .theme:
            return []
        case .providers:
            return AIProvider.allCases.filter { !isExperimentalProvider($0) }
        case .experimental:
            return AIProvider.allCases.filter { isExperimentalProvider($0) }
        }
    }

    private func settingsTab(for provider: AIProvider) -> SettingsTab {
        isExperimentalProvider(provider) ? .experimental : .providers
    }

    private func experimentalToggleBinding(for provider: AIProvider) -> Binding<Bool> {
        switch provider {
        case .claudeCode:
            return $isClaudeCodeEnabled
        case .openAICodex:
            return $isCodexEnabled
        default:
            return .constant(true)
        }
    }

    private func isExperimentalProvider(_ provider: AIProvider) -> Bool {
        provider == .claudeCode || provider == .openAICodex
    }
}
