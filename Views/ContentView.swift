//
//  ContentView.swift
//  AI Chat
//
//  Created by Lasse Vestergaard on 10/02/2026.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @AppStorage("selected_model_reference") private var selectedModelReference: String = ""
    @AppStorage("selected_thread_id") private var selectedThreadIDRaw: String = ""

    @State private var models: [LLMModel] = []
    @State private var isLoadingModels = false
    @State private var isSending = false
    @State private var statusMessage: String?
    @State private var searchText: String = ""

    @State private var threads: [ChatThread] = [
        ChatThread(
            id: UUID(),
            title: "Welcome Chat",
            messages: [
                ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    text: "Open Settings, add provider API keys, fetch models, then start chatting.",
                    timestamp: .now.addingTimeInterval(-120)
                )
            ]
        )
    ]

    @State private var selectedThreadID: UUID?
    @State private var draft: String = ""
    @State private var pendingAttachments: [Attachment] = []
    @State private var openAIAPIKey: String = ""
    @State private var anthropicAPIKey: String = ""
    @State private var openRouterAPIKey: String = ""
    @State private var vercelAIAPIKey: String = ""
    @State private var geminiAPIKey: String = ""
    @State private var didLoadAPIKeys = false
    @State private var isShowingSettings = false
    @State private var isShowingModelPicker = false
    @State private var modelSearchText: String = ""
    @State private var streamingMessageID: UUID?
    @State private var persistWorkItem: DispatchWorkItem?
    @State private var streamingTask: Task<Void, Never>?
    @State private var threadToDelete: ChatThread?
    @State private var isCommandPaletteOpen: Bool = false
    @StateObject private var mcpManager = MCPManager.shared
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.appTheme) private var theme
    @Environment(\.toastManager) private var toastManager

    private var selectedThreadIndex: Int? {
        guard let id = selectedThreadID else { return nil }
        return threads.firstIndex(where: { $0.id == id })
    }

    private var selectedModel: LLMModel? {
        models.first(where: { $0.reference == selectedModelReference })
    }

    private var selectedModelLabel: String {
        if let selectedModel {
            return selectedModel.displayName
        }
        return "Select model"
    }

    private var modelCounts: [AIProvider: Int] {
        models.reduce(into: [:]) { partialResult, model in
            partialResult[model.provider, default: 0] += 1
        }
    }

    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
            && selectedThreadIndex != nil
            && selectedModel != nil
            && !isSending
    }

    private var filteredThreads: [ChatThread] {
        if searchText.isEmpty {
            return threads
        }
        return threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(searchText) ||
            thread.messages.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var currentMessages: [ChatMessage] {
        guard let idx = selectedThreadIndex else { return [] }
        return threads[idx].messages
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredThreads) { thread in
                            let isSelected = thread.id == selectedThreadID
                            Button {
                                selectedThreadID = thread.id
                            } label: {
                                ThreadRow(thread: thread, isSelected: isSelected)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? theme.selectionBackground : Color.clear)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    exportThreadToMarkdown(thread)
                                } label: {
                                    Label("Export to Markdown", systemImage: "doc.text")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    threadToDelete = thread
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }

                theme.divider.frame(height: 1)

                // Bottom toolbar with settings
                HStack {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.sidebarBackground)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createThread()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Chat")
                }
            }
        } detail: {
            VStack(spacing: 0) {
                // Main content area
                if currentMessages.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundStyle(theme.textTertiary)
                        if statusMessage != nil {
                            Text(statusMessage!)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    Spacer()
                } else {
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(currentMessages) { message in
                                    let isLastAssistant = message.role == .assistant
                                        && message.id == currentMessages.last(where: { $0.role == .assistant })?.id
                                    MessageRow(
                                        message: message,
                                        isStreaming: message.id == streamingMessageID,
                                        isLastAssistant: isLastAssistant && !isSending
                                    ) {
                                        retryLastResponse()
                                    }
                                    .id(message.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                        }
                        .onChange(of: currentMessages.count) { _, _ in
                            if let lastID = currentMessages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: currentMessages.last?.text ?? "") { _, _ in
                            if let lastID = currentMessages.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                // Composer at bottom
                ChatComposerView(
                    draft: $draft,
                    attachments: $pendingAttachments,
                    isSending: isSending,
                    canSend: canSend
                ) {
                    startSend()
                } onStop: {
                    stopStreaming()
                }
            }
            .background(theme.background)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    modelMenu
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                openAIAPIKey: $openAIAPIKey,
                anthropicAPIKey: $anthropicAPIKey,
                openRouterAPIKey: $openRouterAPIKey,
                vercelAIAPIKey: $vercelAIAPIKey,
                geminiAPIKey: $geminiAPIKey,
                isLoadingModels: isLoadingModels,
                modelCounts: modelCounts,
                statusMessage: statusMessage
            ) {
                Task { await fetchModels() }
            } onClose: {
                isShowingSettings = false
            }
        }
        .alert("Delete Chat", isPresented: Binding(
            get: { threadToDelete != nil },
            set: { if !$0 { threadToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                threadToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let thread = threadToDelete {
                    let title = thread.title
                    threads.removeAll { $0.id == thread.id }
                    if selectedThreadID == thread.id {
                        selectedThreadID = threads.first?.id
                    }
                    toastManager.show(.success("Deleted \"\(title)\"", icon: "trash"))
                }
                threadToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(threadToDelete?.title ?? "this chat")\"? This cannot be undone.")
        }
        .onAppear {
            if !didLoadAPIKeys {
                loadAPIKeysFromKeychain()
                didLoadAPIKeys = true
            }

            loadChatsFromDisk()

            if let persistedID = UUID(uuidString: selectedThreadIDRaw),
                threads.contains(where: { $0.id == persistedID })
            {
                selectedThreadID = persistedID
            }

            if selectedThreadID == nil {
                selectedThreadID = threads.first?.id
            }

            if models.isEmpty {
                Task { await fetchModels() }
            }

            // Connect to MCP servers
            Task { await mcpManager.loadAndConnect() }
        }
        .onDisappear {
            stopStreaming()
        }
        .onChange(of: openAIAPIKey) { _, newValue in
            persistAPIKeyToKeychain(newValue, for: .openAI)
        }
        .onChange(of: anthropicAPIKey) { _, newValue in
            persistAPIKeyToKeychain(newValue, for: .anthropic)
        }
        .onChange(of: openRouterAPIKey) { _, newValue in
            persistAPIKeyToKeychain(newValue, for: .openRouter)
        }
        .onChange(of: vercelAIAPIKey) { _, newValue in
            persistAPIKeyToKeychain(newValue, for: .vercelAI)
        }
        .onChange(of: geminiAPIKey) { _, newValue in
            persistAPIKeyToKeychain(newValue, for: .gemini)
        }
        .onChange(of: selectedThreadID) { _, newValue in
            selectedThreadIDRaw = newValue?.uuidString ?? ""
        }
        .onChange(of: threads) { _, newValue in
            schedulePersist(newValue)
        }
        .overlay {
            CommandPaletteOverlay(
                isPresented: $isCommandPaletteOpen,
                actions: commandPaletteActions
            )
        }
        .commandPaletteShortcut(isPresented: $isCommandPaletteOpen)
    }

    // MARK: - Command Palette Actions

    private var commandPaletteActions: [CommandAction] {
        var actions: [CommandAction] = []

        // New Chat
        actions.append(CommandAction(
            title: "New Chat",
            subtitle: "Start a fresh conversation",
            icon: "square.and.pencil",
            shortcut: "N"
        ) {
            createThread()
            toastManager.show(.success("New chat created", icon: "square.and.pencil"))
        })

        // Current chat actions (if a thread is selected)
        if let threadID = selectedThreadID,
           let thread = threads.first(where: { $0.id == threadID }) {
            actions.append(CommandAction(
                title: "Export Current Chat",
                subtitle: "Save \"\(thread.title)\" as Markdown",
                icon: "doc.text",
                shortcut: "E"
            ) {
                exportThreadToMarkdown(thread)
            })

            actions.append(CommandAction(
                title: "Delete Current Chat",
                subtitle: "Remove \"\(thread.title)\"",
                icon: "trash",
                shortcut: "D"
            ) {
                threadToDelete = thread
            })
        }

        // Settings
        actions.append(CommandAction(
            title: "Open Settings",
            subtitle: "Configure API keys and theme",
            icon: "gearshape",
            shortcut: ","
        ) {
            isShowingSettings = true
            toastManager.show(.info("Settings opened", icon: "gearshape"))
        })

        // Model picker
        actions.append(CommandAction(
            title: "Change Model",
            subtitle: selectedModelLabel,
            icon: "cpu",
            shortcut: "M"
        ) {
            isShowingModelPicker = true
            toastManager.show(.info("Model picker opened", icon: "cpu"))
        })

        // Fetch models
        actions.append(CommandAction(
            title: "Fetch Models",
            subtitle: "Refresh available models from providers",
            icon: "arrow.clockwise",
            shortcut: "R"
        ) {
            toastManager.show(.info("Fetching models...", icon: "arrow.clockwise"))
            Task { await fetchModels() }
        })

        // Theme picker - shows theme options when searched
        actions.append(CommandAction(
            title: "Theme: System",
            subtitle: themeManager.current.id == "system" ? "Currently active" : "Use macOS appearance",
            icon: "circle.lefthalf.filled"
        ) {
            themeManager.select(.system)
            toastManager.show(.success("Switched to System theme", icon: "circle.lefthalf.filled"))
        })

        actions.append(CommandAction(
            title: "Theme: Tokyo Night",
            subtitle: themeManager.current.id == "tokyo-night" ? "Currently active" : "Dark theme inspired by Tokyo",
            icon: "moon.stars"
        ) {
            themeManager.select(.tokyoNight)
            toastManager.show(.success("Switched to Tokyo Night", icon: "moon.stars"))
        })

        actions.append(CommandAction(
            title: "Theme: Tokyo Night Storm",
            subtitle: themeManager.current.id == "tokyo-night-storm" ? "Currently active" : "Lighter Tokyo Night variant",
            icon: "cloud.moon"
        ) {
            themeManager.select(.tokyoNightStorm)
            toastManager.show(.success("Switched to Tokyo Night Storm", icon: "cloud.moon"))
        })

        actions.append(CommandAction(
            title: "Theme: Catppuccin Mocha",
            subtitle: themeManager.current.id == "catppuccin-mocha" ? "Currently active" : "Warm pastel dark theme",
            icon: "cup.and.saucer"
        ) {
            themeManager.select(.catppuccinMocha)
            toastManager.show(.success("Switched to Catppuccin Mocha", icon: "cup.and.saucer"))
        })

        actions.append(CommandAction(
            title: "Theme: GitHub Dark",
            subtitle: themeManager.current.id == "github-dark" ? "Currently active" : "Clean GitHub-style dark theme",
            icon: "chevron.left.forwardslash.chevron.right"
        ) {
            themeManager.select(.githubDark)
            toastManager.show(.success("Switched to GitHub Dark", icon: "chevron.left.forwardslash.chevron.right"))
        })

        // Stop streaming
        if streamingTask != nil {
            actions.insert(CommandAction(
                title: "Stop Generation",
                subtitle: "Cancel the current response",
                icon: "stop.circle",
                shortcut: "."
            ) {
                stopStreaming()
                toastManager.show(.info("Generation stopped", icon: "stop.circle"))
            }, at: 0)
        }

        // Copy last response
        if let threadID = selectedThreadID,
           let thread = threads.first(where: { $0.id == threadID }),
           let lastAssistant = thread.messages.last(where: { $0.role == .assistant }) {
            actions.append(CommandAction(
                title: "Copy Last Response",
                subtitle: "Copy assistant's last message",
                icon: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lastAssistant.text, forType: .string)
                toastManager.show(.success("Copied to clipboard", icon: "doc.on.doc"))
            })
        }

        // Clear all chats
        actions.append(CommandAction(
            title: "Clear All Chats",
            subtitle: "Remove all conversations",
            icon: "trash.fill"
        ) {
            threads = [ChatThread(id: UUID(), title: "New Chat", messages: [])]
            selectedThreadID = threads.first?.id
            toastManager.show(.success("All chats cleared", icon: "trash"))
        })

        return actions
    }

    private var modelMenu: some View {
        Button {
            isShowingModelPicker.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(selectedModelLabel)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(theme.textPrimary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 260)
        .popover(isPresented: $isShowingModelPicker, arrowEdge: .bottom) {
            ModelPickerPopover(
                models: models,
                selectedModelReference: $selectedModelReference,
                searchText: $modelSearchText,
                isPresented: $isShowingModelPicker
            )
        }
    }

    private func createThread() {
        let thread = ChatThread(id: UUID(), title: "New Chat", messages: [])
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }

    private func exportThreadToMarkdown(_ thread: ChatThread) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var markdown = "# \(thread.title)\n\n"
        
        for message in thread.messages {
            let role: String
            switch message.role {
            case .user: role = "**User**"
            case .assistant: role = "**Assistant**"
            case .tool: role = "**Tool** (\(message.toolName ?? "unknown"))"
            }
            let timestamp = dateFormatter.string(from: message.timestamp)
            markdown += "\(role) — _\(timestamp)_\n\n"
            markdown += "\(message.text)\n\n---\n\n"
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "\(thread.title).md"
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                toastManager.show(.success("Exported \"\(thread.title)\"", icon: "doc.text"))
            } catch {
                toastManager.show(.error("Failed to export: \(error.localizedDescription)"))
            }
        }
    }

    private func adapter(for provider: AIProvider) -> any LLMProviderAdapter {
        switch provider {
        case .openAI:
            return OpenAIAdapter()
        case .anthropic:
            return AnthropicAdapter()
        case .openRouter:
            return OpenRouterAdapter()
        case .vercelAI:
            return VercelAIAdapter()
        case .gemini:
            return GeminiAdapter()
        }
    }

    private func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .openAI:
            return openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic:
            return anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openRouter:
            return openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .vercelAI:
            return vercelAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini:
            return geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func loadChatsFromDisk() {
        do {
            if let loaded = try ChatPersistence.load(), !loaded.isEmpty {
                threads = loaded
            }
        } catch {
            statusMessage = "Failed loading chats: \(error.localizedDescription)"
        }
    }

    private func persistChats(_ threads: [ChatThread]) {
        do {
            try ChatPersistence.save(threads)
        } catch {
            statusMessage = "Failed saving chats: \(error.localizedDescription)"
        }
    }

    private func schedulePersist(_ threads: [ChatThread]) {
        if isSending { return }
        persistWorkItem?.cancel()
        let snapshot = threads
        let workItem = DispatchWorkItem {
            persistChats(snapshot)
        }
        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func startSend() {
        guard streamingTask == nil else { return }
        streamingTask = Task {
            await sendMessage()
            await MainActor.run {
                streamingTask = nil
            }
        }
    }

    /// Remove the last assistant message and re-send the last user message.
    private func retryLastResponse() {
        guard let idx = selectedThreadIndex, !isSending else { return }
        // Remove the last assistant message
        if let lastAssistantIdx = threads[idx].messages.lastIndex(where: { $0.role == .assistant }) {
            threads[idx].messages.remove(at: lastAssistantIdx)
        }
        // Re-send without touching draft — reuse existing history
        guard streamingTask == nil else { return }
        streamingTask = Task {
            await resendFromHistory()
            await MainActor.run {
                streamingTask = nil
            }
        }
    }

    /// Resend using existing thread history (no new user message).
    @MainActor
    private func resendFromHistory() async {
        guard let idx = selectedThreadIndex else { return }
        guard let selectedModel else {
            statusMessage = "Select a model first."
            return
        }

        let threadID = threads[idx].id
        let key = apiKey(for: selectedModel.provider)

        guard !key.isEmpty else {
            statusMessage = "Missing \(selectedModel.provider.rawValue) API key."
            return
        }
        guard !threads[idx].messages.isEmpty else { return }

        isSending = true
        statusMessage = nil

        defer {
            isSending = false
            streamingMessageID = nil
            persistChats(threads)
        }

        await performStreamingLoop(
            threadID: threadID,
            threadIndex: idx,
            model: selectedModel,
            apiKey: key
        )
    }

    private func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func loadAPIKeysFromKeychain() {
        do {
            if let key = try KeychainStore.loadString(for: AIProvider.openAI.keychainAccount) {
                openAIAPIKey = key
            }
            if let key = try KeychainStore.loadString(for: AIProvider.anthropic.keychainAccount) {
                anthropicAPIKey = key
            }
            if let key = try KeychainStore.loadString(for: AIProvider.openRouter.keychainAccount) {
                openRouterAPIKey = key
            }
            if let key = try KeychainStore.loadString(for: AIProvider.vercelAI.keychainAccount) {
                vercelAIAPIKey = key
            }
            if let key = try KeychainStore.loadString(for: AIProvider.gemini.keychainAccount) {
                geminiAPIKey = key
            }
        } catch {
            statusMessage = "Failed loading API keys: \(error.localizedDescription)"
        }
    }

    private func persistAPIKeyToKeychain(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try KeychainStore.deleteValue(for: provider.keychainAccount)
            } else {
                try KeychainStore.saveString(trimmed, for: provider.keychainAccount)
            }
        } catch {
            statusMessage = "Failed saving API key to Keychain: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func fetchModels() async {
        var collected: [LLMModel] = []
        var errors: [String] = []

        isLoadingModels = true
        defer { isLoadingModels = false }

        for provider in AIProvider.allCases {
            let key = apiKey(for: provider)
            guard !key.isEmpty else { continue }

            do {
                let providerModels = try await adapter(for: provider).fetchModels(apiKey: key)
                collected.append(contentsOf: providerModels)
            } catch {
                errors.append("\(provider.rawValue): \(error.localizedDescription)")
            }
        }

        if collected.isEmpty && errors.isEmpty {
            statusMessage = "Add at least one provider API key in Settings first."
            return
        }

        collected.sort { lhs, rhs in
            if lhs.provider != rhs.provider {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        models = collected

        if !models.contains(where: { $0.reference == selectedModelReference }) {
            selectedModelReference = models.first?.reference ?? ""
        }

        var parts: [String] = []
        for provider in AIProvider.allCases {
            let count = collected.filter { $0.provider == provider }.count
            if count > 0 {
                parts.append("\(provider.rawValue): \(count)")
            }
        }

        let loadedMessage = parts.isEmpty ? "No models loaded." : "Loaded \(parts.joined(separator: " · "))."
        if errors.isEmpty {
            statusMessage = loadedMessage
        } else {
            statusMessage = "\(loadedMessage) Errors: \(errors.joined(separator: " | "))"
        }
    }

    @MainActor
    private func sendMessage() async {
        guard let idx = selectedThreadIndex else { return }
        guard let selectedModel else {
            statusMessage = "Select a model first."
            return
        }

        let threadID = threads[idx].id
        let key = apiKey(for: selectedModel.provider)
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty else {
            statusMessage = "Missing \(selectedModel.provider.rawValue) API key."
            return
        }
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        let messageAttachments = pendingAttachments
        draft = ""
        pendingAttachments = []
        isSending = true
        statusMessage = nil

        let userMessage = ChatMessage(id: UUID(), role: .user, text: text, timestamp: .now, attachments: messageAttachments)
        threads[idx].messages.append(userMessage)
        if threads[idx].title == "New Chat" {
            threads[idx].title = String(text.prefix(40))
        }

        defer {
            isSending = false
            streamingMessageID = nil
            persistChats(threads)
        }

        await performStreamingLoop(
            threadID: threadID,
            threadIndex: idx,
            model: selectedModel,
            apiKey: key
        )
    }

    // MARK: - Tool-Use Streaming Loop

    /// Performs the streaming loop: sends to LLM, handles tool calls, re-sends with results.
    /// Loops until the LLM produces a response with no tool calls (max 10 iterations).
    @MainActor
    private func performStreamingLoop(
        threadID: UUID,
        threadIndex: Int,
        model: LLMModel,
        apiKey: String
    ) async {
        let maxToolIterations = 5
        var previousToolCallSignature: String? = nil

        for _ in 0..<maxToolIterations {
            // Build history from current thread messages
            guard let idx = threads.firstIndex(where: { $0.id == threadID }) else { return }

            let history = threads[idx].messages.map { message -> LLMChatMessage in
                let role: ChatRole = {
                    switch message.role {
                    case .user: return .user
                    case .assistant: return .assistant
                    case .tool: return .tool
                    }
                }()

                let toolCalls = (message.toolCalls ?? []).map {
                    ToolCallInfo(id: $0.id, name: $0.name, arguments: $0.arguments, serverName: $0.serverName)
                }

                let toolResult: ToolResultInfo? = {
                    if message.role == .tool, let tcID = message.toolCallID, let name = message.toolName {
                        return ToolResultInfo(toolCallID: tcID, toolName: name, content: message.text, isError: false)
                    }
                    return nil
                }()

                return LLMChatMessage(
                    role: role,
                    content: message.text,
                    attachments: message.attachments,
                    toolCalls: toolCalls,
                    toolResult: toolResult
                )
            }

            // Create assistant placeholder
            let assistantID = UUID()
            threads[idx].messages.append(
                ChatMessage(id: assistantID, role: .assistant, text: "", timestamp: .now)
            )
            streamingMessageID = assistantID

            do {
                let result = try await adapter(for: model.provider).streamMessage(
                    history: history,
                    modelID: model.modelID,
                    apiKey: apiKey,
                    tools: mcpManager.tools
                ) { event in
                    await MainActor.run {
                        switch event {
                        case .textDelta(let delta):
                            appendStreamDelta(delta, to: assistantID, in: threadID)
                        case .toolCallStart(_, _, _):
                            // Append visual indicator that a tool is being called
                            if messageText(for: assistantID, in: threadID).isEmpty {
                                // Will be replaced once we have the full tool call info
                            }
                            break
                        case .toolCallArgumentDelta(_, _):
                            break
                        case .done:
                            break
                        }
                    }
                }

                // Check if there are tool calls to execute
                if !result.toolCalls.isEmpty {
                    // Detect repeated identical tool calls to prevent infinite loops
                    let currentSignature = result.toolCalls.map { "\($0.name):\($0.arguments)" }.joined(separator: "|")
                    if currentSignature == previousToolCallSignature {
                        // Model is repeating the same tool call — break out
                        if messageText(for: assistantID, in: threadID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            setMessageText("The model repeated the same tool call. Stopping to prevent a loop.", for: assistantID, in: threadID)
                        }
                        return
                    }
                    previousToolCallSignature = currentSignature

                    // Update the assistant message with tool call info
                    guard let threadIdx = threads.firstIndex(where: { $0.id == threadID }),
                          let msgIdx = threads[threadIdx].messages.firstIndex(where: { $0.id == assistantID }) else {
                        return
                    }

                    // Map tool call server names from MCPTool registry
                    let resolvedToolCalls = result.toolCalls.map { tc -> ChatMessage.ToolCall in
                        let serverName = mcpManager.tools.first(where: { $0.name == tc.name })?.serverName ?? ""
                        return ChatMessage.ToolCall(id: tc.id, name: tc.name, arguments: tc.arguments, serverName: serverName)
                    }
                    threads[threadIdx].messages[msgIdx].toolCalls = resolvedToolCalls

                    // Execute each tool call and add results to the thread
                    for tc in resolvedToolCalls {
                        let toolResultText: String

                        do {
                            // Parse arguments
                            let args: [String: Any]
                            if let data = tc.arguments.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                args = dict
                            } else {
                                args = [:]
                            }

                            let mcpResult = try await mcpManager.callTool(
                                serverName: tc.serverName,
                                toolName: tc.name,
                                arguments: args
                            )

                            // Concatenate text content from the result
                            toolResultText = mcpResult.content
                                .compactMap { $0.text }
                                .joined(separator: "\n")
                        } catch {
                            toolResultText = "Error executing tool: \(error.localizedDescription)"
                        }

                        // Add tool result message to thread
                        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else { return }
                        let toolMessage = ChatMessage(
                            id: UUID(),
                            role: .tool,
                            text: toolResultText,
                            timestamp: .now,
                            toolCallID: tc.id,
                            toolName: tc.name
                        )
                        threads[tIdx].messages.append(toolMessage)
                    }

                    // Continue the loop — LLM will process tool results
                    continue
                }

                // No tool calls — we're done
                if messageText(for: assistantID, in: threadID).trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    setMessageText("No response from model.", for: assistantID, in: threadID)
                    statusMessage = "The model returned an empty response."
                }
                return

            } catch {
                if error is CancellationError {
                    statusMessage = "Response stopped."
                    if messageText(for: assistantID, in: threadID).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty {
                        setMessageText("Stopped.", for: assistantID, in: threadID)
                    }
                    return
                }

                let text = "Request failed: \(error.localizedDescription)"
                if messageText(for: assistantID, in: threadID).trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    setMessageText(text, for: assistantID, in: threadID)
                } else {
                    setMessageText(
                        "\(messageText(for: assistantID, in: threadID))\n\n\(text)", for: assistantID,
                        in: threadID)
                }
                statusMessage = text
                return
            }
        }

        // If we hit max iterations, add a note
        statusMessage = "Tool use loop reached maximum iterations."
    }

    private func appendStreamDelta(_ delta: String, to messageID: UUID, in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
            let messageIndex = threads[threadIndex].messages.firstIndex(where: {
                $0.id == messageID
            })
        else {
            return
        }
        threads[threadIndex].messages[messageIndex].text.append(delta)
    }

    private func setMessageText(_ newText: String, for messageID: UUID, in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
            let messageIndex = threads[threadIndex].messages.firstIndex(where: {
                $0.id == messageID
            })
        else {
            return
        }
        threads[threadIndex].messages[messageIndex].text = newText
    }

    private func messageText(for messageID: UUID, in threadID: UUID) -> String {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
            let messageIndex = threads[threadIndex].messages.firstIndex(where: {
                $0.id == messageID
            })
        else {
            return ""
        }
        return threads[threadIndex].messages[messageIndex].text
    }
}
