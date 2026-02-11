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
    @AppStorage("codex_sandbox_mode") private var codexSandboxModeRaw: String = CodexSandboxMode
        .readOnly.rawValue
    @AppStorage("experimental_claude_code_enabled") private var isClaudeCodeEnabled = false
    @AppStorage("experimental_codex_enabled") private var isCodexEnabled = false
    @AppStorage("auto_scroll_enabled") private var isAutoScrollEnabled = true

    @State private var models: [LLMModel] = []
    @State private var isLoadingModels = false
    @State private var isSending = false
    @State private var statusMessage: String?
    @State private var searchText: String = ""

    // MARK: - Search Debouncing
    /// Debounced search text for filtering (updates 200ms after user stops typing)
    @State private var debouncedSearchText: String = ""
    private let searchDebounceInterval: TimeInterval = 0.2
    @State private var searchDebounceWorkItem: DispatchWorkItem?

    @State private var threads: [ChatThread] = [
        ChatThread(
            id: UUID(),
            title: "New Chat",
            messages: []
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
    @State private var kimiAPIKey: String = ""
    @State private var didLoadAPIKeys = false
    @State private var isShowingSettings = false
    @State private var streamingMessageID: UUID?
    @State private var persistWorkItem: DispatchWorkItem?
    @State private var streamingTask: Task<Void, Never>?

    // MARK: - Streaming Batching
    /// Buffers streaming text deltas to batch UI updates (reduces per-token lag)
    @State private var streamBuffer: String = ""
    @State private var streamBufferMessageID: UUID?
    @State private var streamBufferThreadID: UUID?
    @State private var streamFlushWorkItem: DispatchWorkItem?

    // MARK: - Scroll Throttling
    /// Tracks last scroll time to throttle scrollTo calls to ~30fps
    @State private var lastScrollTime: Date = Date.distantPast
    private let scrollThrottleInterval: TimeInterval = 0.033  // ~30fps

    // MARK: - Smart Scroll Position Tracking
    /// Tracks whether user is scrolled up (reading older messages)
    @State private var isUserScrolledUp: Bool = false
    /// Shows if new messages arrived while user was scrolled up
    @State private var hasUnreadMessages: Bool = false
    /// The scroll offset to determine if user is near bottom
    @State private var scrollOffset: CGFloat = 0
    /// Threshold for considering user "at bottom" (in points)
    private let scrollBottomThreshold: CGFloat = 200
    /// Timestamp updated when streaming text changes to trigger scroll
    @State private var lastStreamUpdate: Date = Date.distantPast

    @State private var threadToDelete: ChatThread?
    @State private var isCommandPaletteOpen: Bool = false
    @State private var agentToolExecutor = AgentToolExecutor()
    @State private var pendingToolConfirmation: PendingToolConfirmation?
    @State private var isShowingAgentDirectoryPicker = false
    @State private var undoHistoryByThread: [UUID: [UndoEntry]] = [:]
    @State private var isShowingUndoPanel = false
    @State private var isShowingDeleteAllChatsAlert = false
    @State private var isShowingRightSidebar = false
    @StateObject private var mcpManager = MCPManager.shared
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appUpdater: AppUpdater
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
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingAttachments.isEmpty)
            && selectedThreadIndex != nil
            && selectedModel != nil
            && !isSending
    }

    private var filteredThreads: [ChatThread] {
        if debouncedSearchText.isEmpty {
            return threads
        }
        return threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(debouncedSearchText)
                || thread.messages.contains {
                    $0.text.localizedCaseInsensitiveContains(debouncedSearchText)
                }
        }
    }

    private var currentMessages: [ChatMessage] {
        guard let idx = selectedThreadIndex else { return [] }
        return threads[idx].messages
    }

    /// Undo history for the currently selected thread.
    private var undoHistory: [UndoEntry] {
        guard let id = selectedThreadID else { return [] }
        return undoHistoryByThread[id] ?? []
    }

    /// Context token usage for the currently selected thread.
    private var currentContextUsage: ThreadTokenUsage? {
        guard let idx = selectedThreadIndex else { return nil }
        let thread = threads[idx]

        // Get the context window from the selected model
        let contextWindow = selectedModel?.contextWindow ?? 128_000

        // Calculate estimated tokens for current messages
        let estimatedTokens = TokenEstimator.estimateTotalTokens(for: thread.messages)

        // Use existing usage data if available, otherwise create new
        if var usage = thread.tokenUsage {
            // Update with current estimate if no actual usage yet
            if usage.actualTokens == nil {
                usage.updateEstimated(estimatedTokens)
            }
            return usage
        } else {
            return ThreadTokenUsage(
                estimatedTokens: estimatedTokens,
                contextWindow: contextWindow
            )
        }
    }

    /// Binding to the selected thread's agentEnabled flag.
    private var agentEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                guard let idx = selectedThreadIndex else { return false }
                return threads[idx].agentEnabled
            },
            set: { newValue in
                guard let idx = selectedThreadIndex else { return }
                threads[idx].agentEnabled = newValue
            }
        )
    }

    /// Binding to the selected thread's working directory.
    private var workingDirectoryBinding: Binding<String?> {
        Binding(
            get: {
                guard let idx = selectedThreadIndex else { return nil }
                return threads[idx].workingDirectory
            },
            set: { newValue in
                guard let idx = selectedThreadIndex else { return }
                threads[idx].workingDirectory = newValue
            }
        )
    }

    /// Binding to the selected thread's dangerous mode flag.
    private var dangerousModeBinding: Binding<Bool> {
        Binding(
            get: {
                guard let idx = selectedThreadIndex else { return false }
                return threads[idx].dangerousMode
            },
            set: { newValue in
                guard let idx = selectedThreadIndex else { return }
                threads[idx].dangerousMode = newValue
            }
        )
    }

    var body: some View { mainView }

    private var mainView: some View { buildMainView() }

    private func buildMainView() -> AnyView {
        let base = splitView

        let dialogs =
            base
            .sheet(isPresented: $isShowingSettings) { settingsSheet }
            .alert(
                "Delete Chat",
                isPresented: Binding(
                    get: { threadToDelete != nil },
                    set: { if !$0 { threadToDelete = nil } }
                )
            ) {
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
                Text(
                    "Are you sure you want to delete \"\(threadToDelete?.title ?? "this chat")\"? This cannot be undone."
                )
            }
            .alert("Delete All Chats", isPresented: $isShowingDeleteAllChatsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    clearAllChats(showToast: true)
                }
            } message: {
                Text("This removes all conversations and cannot be undone.")
            }

        let lifecycle =
            dialogs
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

                Task { await mcpManager.loadAndConnect() }
            }
            .onDisappear {
                stopStreaming()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                isShowingSettings = true
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
            .onChange(of: kimiAPIKey) { _, newValue in
                persistAPIKeyToKeychain(newValue, for: .kimi)
            }
            .onChange(of: selectedThreadID) { _, newValue in
                selectedThreadIDRaw = newValue?.uuidString ?? ""
            }
            .onChange(of: threads) { _, newValue in
                schedulePersist(newValue)
            }

        let decorated =
            lifecycle
            .overlay {
                CommandPaletteOverlay(
                    isPresented: $isCommandPaletteOpen,
                    actions: commandPaletteActions
                )
            }
            .overlay {
                if let confirmation = pendingToolConfirmation {
                    toolConfirmationOverlay(confirmation)
                }
            }
            .overlay {
                if isShowingUndoPanel {
                    undoPanelOverlay
                }
            }
            .commandPaletteShortcut(isPresented: $isCommandPaletteOpen)
            .fileImporter(
                isPresented: $isShowingAgentDirectoryPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first,
                    let idx = selectedThreadIndex
                {
                    threads[idx].workingDirectory = url.path
                    threads[idx].agentEnabled = true
                    let abbreviated = abbreviatePathForToast(url.path)
                    toastManager.show(.success("Agent mode ON • \(abbreviated)"))
                }
            }

        return AnyView(decorated)
    }

    private var splitView: some View {
        HSplitView {
            // Left sidebar - chat list
            sidebarView
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            
            // Center - main chat area
            detailView
                .frame(minWidth: 400)
            
            // Right sidebar - configuration (optional)
            if isShowingRightSidebar {
                rightSidebarView
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            }
        }
    }
    
    private var rightSidebarView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat Configuration")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                
                Spacer()
                
                Button {
                    isShowingRightSidebar = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            theme.hoverBackground,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            theme.divider.frame(height: 1)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // System Prompt Section
                    systemPromptSection
                    
                    theme.divider.frame(height: 1)
                    
                    // Thread Info Section
                    threadInfoSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            
            Spacer()
        }
        .background(theme.sidebarBackground)
    }
    
    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                
                Text("System Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                
                Spacer()
                
                if !systemPromptBinding.wrappedValue.isEmpty {
                    Button {
                        systemPromptBinding.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear system prompt")
                }
            }
            
            Text("Customize the AI's behavior for this conversation.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
            
            TextEditor(text: systemPromptBinding)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .background(theme.codeBackground)
                .frame(minHeight: 120, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.codeBorder, lineWidth: 1)
                )
        }
    }
    
    private var threadInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                
                Text("Thread Info")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            
            if let idx = selectedThreadIndex {
                let thread = threads[idx]
                
                InfoRow(label: "Messages", value: "\(thread.messages.count)")
                InfoRow(label: "Agent Mode", value: thread.agentEnabled ? "On" : "Off")
                if let dir = thread.workingDirectory {
                    InfoRow(label: "Working Dir", value: String(dir.prefix(30)) + (dir.count > 30 ? "..." : ""))
                }
                if let modelRef = thread.modelReference {
                    InfoRow(label: "Model", value: modelRef)
                }
            } else {
                Text("No chat selected")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
    
    private var systemPromptBinding: Binding<String> {
        Binding(
            get: {
                guard let idx = selectedThreadIndex else { return "" }
                return threads[idx].systemPrompt ?? ""
            },
            set: { newValue in
                guard let idx = selectedThreadIndex else { return }
                threads[idx].systemPrompt = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search bar at the top
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                
                TextField("Search", text: $searchText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.hoverBackground)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Chats")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)

                        Spacer()

                        Button {
                            createThread()
                        } label: {
                            Label("New", systemImage: "square.and.pencil")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.textSecondary)
                        .help("New Chat")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

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
                                isShowingDeleteAllChatsAlert = true
                            } label: {
                                Label("Delete All Chats", systemImage: "trash.slash")
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
            .contextMenu {
                Button(role: .destructive) {
                    isShowingDeleteAllChatsAlert = true
                } label: {
                    Label("Delete All Chats", systemImage: "trash.slash")
                }
            }

            theme.divider.frame(height: 1)

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

                Button {
                    appUpdater.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!appUpdater.canCheckForUpdates)
                .help("Check for Updates")

                Spacer()

                Button {
                    isShowingRightSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundStyle(isShowingRightSidebar ? theme.accent : theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Configuration Sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(theme.sidebarBackground)
        .onChange(of: searchText) { _, newValue in
            // Debounce search input by 200ms
            searchDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [self] in
                debouncedSearchText = newValue
            }
            searchDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + searchDebounceInterval, execute: workItem)
        }
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            detailContent
            chatComposerView
        }
        .background(theme.background)
    }

    @ViewBuilder
    private var detailContent: some View {
        if currentMessages.isEmpty {
            emptyStateView
        } else {
            messageListView
        }
    }

    private var emptyStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(theme.textTertiary)

                Text("Start a conversation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)

                Text("Choose a chat in the sidebar or write a message below.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textTertiary)

                if statusMessage != nil {
                    Text(statusMessage!)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                messageScrollView(proxy: proxy)
                newMessagesOverlay(proxy: proxy)
            }
        }
    }

    private func messageScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(currentMessages) { message in
                    messageRow(for: message)
                        .id(message.id)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY)
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
            let isAtBottom = scrollOffset > -scrollBottomThreshold
            if isUserScrolledUp && isAtBottom {
                isUserScrolledUp = false
                hasUnreadMessages = false
            } else if !isUserScrolledUp && !isAtBottom {
                isUserScrolledUp = true
            }
        }
        .onChange(of: currentMessages.count) { _, _ in
            throttledScrollToLast(proxy: proxy)
        }
        .onChange(of: currentMessages.last?.toolCalls?.count ?? 0) { _, _ in
            throttledScrollToLast(proxy: proxy)
        }
        .onChange(of: lastStreamUpdate) { _, _ in
            throttledScrollToLast(proxy: proxy)
        }
    }

    private func newMessagesOverlay(proxy: ScrollViewProxy) -> some View {
        Group {
            if isUserScrolledUp && hasUnreadMessages {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if let lastID = currentMessages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                        isUserScrolledUp = false
                        hasUnreadMessages = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New Messages")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.background)
                            .shadow(
                                color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.accent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var chatComposerView: some View {
        ChatComposerView(
            draft: $draft,
            attachments: $pendingAttachments,
            models: models,
            selectedModelReference: $selectedModelReference,
            agentEnabled: agentEnabledBinding,
            dangerousMode: dangerousModeBinding,
            workingDirectory: workingDirectoryBinding,
            undoCount: undoHistory.filter { !$0.isReverted }.count,
            isSending: isSending,
            canSend: canSend,
            contextUsage: currentContextUsage
        ) {
            startSend()
        } onStop: {
            stopStreaming()
        } onShowUndo: {
            isShowingUndoPanel = true
        }
    }

    // MARK: - Command Palette Actions

    private var commandPaletteActions: [CommandAction] {
        var actions: [CommandAction] = []

        // New Chat
        actions.append(
            CommandAction(
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
            let thread = threads.first(where: { $0.id == threadID })
        {
            actions.append(
                CommandAction(
                    title: "Export Current Chat",
                    subtitle: "Save \"\(thread.title)\" as Markdown",
                    icon: "doc.text",
                    shortcut: "E"
                ) {
                    exportThreadToMarkdown(thread)
                })

            actions.append(
                CommandAction(
                    title: "Delete Current Chat",
                    subtitle: "Remove \"\(thread.title)\"",
                    icon: "trash",
                    shortcut: "D"
                ) {
                    threadToDelete = thread
                })
        }

        // Settings
        actions.append(
            CommandAction(
                title: "Open Settings",
                subtitle: "Configure API keys and theme",
                icon: "gearshape",
                shortcut: ","
            ) {
                isShowingSettings = true
                toastManager.show(.info("Settings opened", icon: "gearshape"))
            })

        // Model picker
        actions.append(
            CommandAction(
                title: "Change Model",
                subtitle: selectedModelLabel,
                icon: "cpu",
                shortcut: "M"
            ) {
                NotificationCenter.default.post(name: .openModelPickerRequested, object: nil)
                toastManager.show(.info("Model picker opened", icon: "cpu"))
            })

        // Fetch models
        actions.append(
            CommandAction(
                title: "Fetch Models",
                subtitle: "Refresh available models from providers",
                icon: "arrow.clockwise",
                shortcut: "R"
            ) {
                toastManager.show(.info("Fetching models...", icon: "arrow.clockwise"))
                Task { await fetchModels() }
            })

        // Check for Updates
        actions.append(
            CommandAction(
                title: "Check for Updates",
                subtitle: "Check for a new version of Humlex",
                icon: "arrow.triangle.2.circlepath",
                shortcut: "U"
            ) {
                appUpdater.checkForUpdates()
            })

        // Theme picker - shows theme options when searched
        actions.append(
            CommandAction(
                title: "Theme: System",
                subtitle: themeManager.current.id == "system"
                    ? "Currently active" : "Use macOS appearance",
                icon: "circle.lefthalf.filled"
            ) {
                themeManager.select(.system)
                toastManager.show(
                    .success("Switched to System theme", icon: "circle.lefthalf.filled"))
            })

        actions.append(
            CommandAction(
                title: "Theme: Tokyo Night",
                subtitle: themeManager.current.id == "tokyo-night"
                    ? "Currently active" : "Dark theme inspired by Tokyo",
                icon: "moon.stars"
            ) {
                themeManager.select(.tokyoNight)
                toastManager.show(.success("Switched to Tokyo Night", icon: "moon.stars"))
            })

        actions.append(
            CommandAction(
                title: "Theme: Tokyo Night Storm",
                subtitle: themeManager.current.id == "tokyo-night-storm"
                    ? "Currently active" : "Lighter Tokyo Night variant",
                icon: "cloud.moon"
            ) {
                themeManager.select(.tokyoNightStorm)
                toastManager.show(.success("Switched to Tokyo Night Storm", icon: "cloud.moon"))
            })

        actions.append(
            CommandAction(
                title: "Theme: Catppuccin Mocha",
                subtitle: themeManager.current.id == "catppuccin-mocha"
                    ? "Currently active" : "Warm pastel dark theme",
                icon: "cup.and.saucer"
            ) {
                themeManager.select(.catppuccinMocha)
                toastManager.show(.success("Switched to Catppuccin Mocha", icon: "cup.and.saucer"))
            })

        actions.append(
            CommandAction(
                title: "Theme: GitHub Dark",
                subtitle: themeManager.current.id == "github-dark"
                    ? "Currently active" : "Clean GitHub-style dark theme",
                icon: "chevron.left.forwardslash.chevron.right"
            ) {
                themeManager.select(.githubDark)
                toastManager.show(
                    .success(
                        "Switched to GitHub Dark", icon: "chevron.left.forwardslash.chevron.right"))
            })

        // Stop streaming
        if streamingTask != nil {
            actions.insert(
                CommandAction(
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
            let lastAssistant = thread.messages.last(where: { $0.role == .assistant })
        {
            actions.append(
                CommandAction(
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
        actions.append(
            CommandAction(
                title: "Clear All Chats",
                subtitle: "Remove all conversations",
                icon: "trash.fill"
            ) {
                clearAllChats(showToast: true)
            })

        // Agent mode toggle
        if let threadID = selectedThreadID,
            let thread = threads.first(where: { $0.id == threadID })
        {
            if thread.agentEnabled {
                actions.append(
                    CommandAction(
                        title: "Disable Agent Mode",
                        subtitle: "Turn off built-in coding tools",
                        icon: "terminal"
                    ) {
                        if let idx = threads.firstIndex(where: { $0.id == threadID }) {
                            threads[idx].agentEnabled = false
                            toastManager.show(.info("Agent mode disabled", icon: "terminal"))
                        }
                    })
            } else {
                actions.append(
                    CommandAction(
                        title: "Enable Agent Mode",
                        subtitle: "Type /agent <path> or pick a folder",
                        icon: "terminal"
                    ) {
                        if let idx = threads.firstIndex(where: { $0.id == threadID }) {
                            if threads[idx].workingDirectory != nil {
                                threads[idx].agentEnabled = true
                                toastManager.show(.success("Agent mode ON", icon: "terminal"))
                            } else {
                                isShowingAgentDirectoryPicker = true
                            }
                        }
                    })
            }
        }

        return actions
    }

    private var settingsSheet: some View {
        SettingsView(
            openAIAPIKey: $openAIAPIKey,
            anthropicAPIKey: $anthropicAPIKey,
            openRouterAPIKey: $openRouterAPIKey,
            vercelAIAPIKey: $vercelAIAPIKey,
            geminiAPIKey: $geminiAPIKey,
            kimiAPIKey: $kimiAPIKey,
            isLoadingModels: isLoadingModels,
            modelCounts: modelCounts,
            statusMessage: statusMessage
        ) {
            Task { await fetchModels() }
        } onClose: {
            isShowingSettings = false
        }
    }

    private func createThread() {
        let thread = ChatThread(id: UUID(), title: "New Chat", messages: [])
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }

    private func clearAllChats(showToast: Bool) {
        threads = [ChatThread(id: UUID(), title: "New Chat", messages: [])]
        selectedThreadID = threads.first?.id
        if showToast {
            toastManager.show(.success("All chats cleared", icon: "trash"))
        }
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
        case .kimi:
            return KimiAdapter()
        case .ollama:
            return OllamaAdapter()
        case .claudeCode:
            var adapter = ClaudeCodeAdapter()
            if let idx = selectedThreadIndex {
                adapter.workingDirectory = threads[idx].workingDirectory
            }
            return adapter
        case .openAICodex:
            var adapter = OpenAICodexAdapter()
            if let idx = selectedThreadIndex {
                adapter.workingDirectory = threads[idx].workingDirectory
            }
            adapter.sandboxMode = CodexSandboxMode(rawValue: codexSandboxModeRaw) ?? .readOnly
            return adapter
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
        case .kimi:
            return kimiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .ollama:
            return ""
        case .claudeCode:
            return "claude-code"  // Sentinel value — Claude Code authenticates via CLI
        case .openAICodex:
            return "codex"  // Sentinel value — Codex authenticates via CLI
        }
    }

    private func isProviderEnabled(_ provider: AIProvider) -> Bool {
        switch provider {
        case .claudeCode:
            return isClaudeCodeEnabled
        case .openAICodex:
            return isCodexEnabled
        default:
            return true
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
        if let lastAssistantIdx = threads[idx].messages.lastIndex(where: { $0.role == .assistant })
        {
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

        guard !key.isEmpty || !selectedModel.provider.requiresAPIKey else {
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
            if let key = try KeychainStore.loadString(for: AIProvider.kimi.keychainAccount) {
                kimiAPIKey = key
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
            guard isProviderEnabled(provider) else { continue }
            let key = apiKey(for: provider)
            guard !key.isEmpty || !provider.requiresAPIKey else { continue }

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
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                == .orderedAscending
        }
        models = collected

        if !models.contains(where: { $0.reference == selectedModelReference }) {
            selectedModelReference = models.first?.reference ?? ""
        }

        var parts: [String] = []
        for provider in AIProvider.allCases {
            guard isProviderEnabled(provider) else { continue }
            let count = collected.filter { $0.provider == provider }.count
            if count > 0 {
                parts.append("\(provider.rawValue): \(count)")
            }
        }

        let loadedMessage =
            parts.isEmpty ? "No models loaded." : "Loaded \(parts.joined(separator: " · "))."
        if errors.isEmpty {
            statusMessage = loadedMessage
        } else {
            statusMessage = "\(loadedMessage) Errors: \(errors.joined(separator: " | "))"
        }
    }

    @MainActor
    private func sendMessage() async {
        guard let idx = selectedThreadIndex else { return }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle /agent slash command
        if text.hasPrefix("/agent") {
            handleAgentCommand(text, threadIndex: idx)
            return
        }

        guard let selectedModel else {
            statusMessage = "Select a model first."
            return
        }

        let threadID = threads[idx].id
        let key = apiKey(for: selectedModel.provider)

        guard !key.isEmpty || !selectedModel.provider.requiresAPIKey else {
            statusMessage = "Missing \(selectedModel.provider.rawValue) API key."
            return
        }
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        let messageAttachments = pendingAttachments
        draft = ""
        pendingAttachments = []
        isSending = true
        statusMessage = nil

        let userMessage = ChatMessage(
            id: UUID(), role: .user, text: text, timestamp: .now, attachments: messageAttachments)
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

    // MARK: - /agent Slash Command

    /// Handle `/agent [path|off]` slash command.
    /// - `/agent` — toggle agent mode; opens folder picker if no directory set
    /// - `/agent off` — disable agent mode
    /// - `/agent <path>` — set working directory and enable agent mode
    private func handleAgentCommand(_ text: String, threadIndex idx: Int) {
        let parts = text.split(separator: " ", maxSplits: 1)
        let argument =
            parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil

        draft = ""

        if let argument {
            if argument.lowercased() == "off" {
                threads[idx].agentEnabled = false
                toastManager.show(.info("Agent mode disabled"))
                return
            }

            // Treat argument as a path
            let path: String
            if argument.hasPrefix("~") {
                path = (argument as NSString).expandingTildeInPath
            } else if argument.hasPrefix("/") {
                path = argument
            } else {
                // Relative to current working directory if one is set, otherwise home
                if let current = threads[idx].workingDirectory {
                    path = (current as NSString).appendingPathComponent(argument)
                } else {
                    path = (NSHomeDirectory() as NSString).appendingPathComponent(argument)
                }
            }

            // Verify the directory exists
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                threads[idx].workingDirectory = path
                threads[idx].agentEnabled = true
                let abbreviated = abbreviatePathForToast(path)
                toastManager.show(.success("Agent mode ON \u{2022} \(abbreviated)"))
            } else {
                toastManager.show(.error("Directory not found: \(argument)"))
            }
        } else {
            // No argument — toggle
            if threads[idx].agentEnabled {
                threads[idx].agentEnabled = false
                toastManager.show(.info("Agent mode disabled"))
            } else if threads[idx].workingDirectory != nil {
                threads[idx].agentEnabled = true
                let abbreviated = abbreviatePathForToast(threads[idx].workingDirectory!)
                toastManager.show(.success("Agent mode ON \u{2022} \(abbreviated)"))
            } else {
                // No directory set — show folder picker
                isShowingAgentDirectoryPicker = true
            }
        }
    }

    private func abbreviatePathForToast(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Tool-Use Streaming Loop

    /// Performs the streaming loop: sends to LLM, handles tool calls, re-sends with results.
    /// Loops until the LLM produces a response with no tool calls.
    /// In agent mode: merges built-in tools, prepends system prompt, routes execution, max 25 iterations.
    @MainActor
    private func performStreamingLoop(
        threadID: UUID,
        threadIndex: Int,
        model: LLMModel,
        apiKey: String
    ) async {
        guard let idx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let isAgent = threads[idx].agentEnabled
        let workDir = threads[idx].workingDirectory
        let maxToolIterations = isAgent ? 25 : 5
        var previousToolCallSignature: String? = nil

        // Merge tools: MCP tools + built-in agent tools (if agent mode is on)
        // Always include fetch tool for normal chat mode
        // Claude Code and Codex handle their own tools internally — don't pass ours
        let isCLIProvider = model.provider == .claudeCode || model.provider == .openAICodex
        let availableTools: [MCPTool] =
            isCLIProvider
            ? []
            : (isAgent
                ? mcpManager.tools + AgentTools.definitions()
                : mcpManager.tools + AgentTools.fetchDefinitions())

        for _ in 0..<maxToolIterations {
            // Build history from current thread messages
            guard let currentIdx = threads.firstIndex(where: { $0.id == threadID }) else { return }

            var history = threads[currentIdx].messages.map { message -> LLMChatMessage in
                let role: ChatRole = {
                    switch message.role {
                    case .user: return .user
                    case .assistant: return .assistant
                    case .tool: return .tool
                    }
                }()

                let toolCalls = (message.toolCalls ?? []).map {
                    ToolCallInfo(
                        id: $0.id,
                        name: $0.name,
                        arguments: $0.arguments,
                        serverName: $0.serverName,
                        thoughtSignature: $0.thoughtSignature
                    )
                }

                let toolResult: ToolResultInfo? = {
                    if message.role == .tool, let tcID = message.toolCallID,
                        let name = message.toolName
                    {
                        return ToolResultInfo(
                            toolCallID: tcID, toolName: name, content: message.text, isError: false)
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

            // Build system prompt: custom prompt + agent tools prompt (if applicable)
            var systemPromptParts: [String] = []
            
            // Add custom system prompt from sidebar if set
            if let customPrompt = threads[currentIdx].systemPrompt, !customPrompt.isEmpty {
                systemPromptParts.append(customPrompt)
            }
            
            // Add agent system prompt (invisible in UI, only sent to LLM)
            if isAgent, let dir = workDir {
                systemPromptParts.append(AgentTools.systemPrompt(workingDirectory: dir))
            } else if !isAgent && availableTools.contains(where: { $0.name == "fetch" }) {
                // Add minimal fetch tool prompt for normal mode
                let fetchPrompt = """
                You have access to the fetch tool for making HTTP requests. Use it to retrieve data from APIs or websites.
                
                fetch parameters:
                - url (required): The URL to fetch
                - method: HTTP method (GET, POST, PUT, DELETE, PATCH) - defaults to GET
                - headers: Optional HTTP headers as key-value pairs
                - body: Request body for POST/PUT/PATCH
                - timeout: Timeout in seconds (default 30, max 60)
                """
                systemPromptParts.append(fetchPrompt)
            }
            
            // Insert combined system prompt at the beginning of history
            if !systemPromptParts.isEmpty {
                let combinedSystemPrompt = systemPromptParts.joined(separator: "\n\n")
                let systemMsg = LLMChatMessage(
                    role: .system,
                    content: combinedSystemPrompt,
                    attachments: [],
                    toolCalls: [],
                    toolResult: nil
                )
                history.insert(systemMsg, at: 0)
            }

            // Create assistant placeholder
            let assistantID = UUID()
            threads[currentIdx].messages.append(
                ChatMessage(id: assistantID, role: .assistant, text: "", timestamp: .now)
            )
            streamingMessageID = assistantID

            do {
                let result = try await adapter(for: model.provider).streamMessage(
                    history: history,
                    modelID: model.modelID,
                    apiKey: apiKey,
                    tools: availableTools
                ) { event in
                    await MainActor.run {
                        switch event {
                        case .textDelta(let delta):
                            bufferStreamDelta(delta, to: assistantID, in: threadID)
                        case .toolCallStart(_, _, _):
                            break
                        case .toolCallArgumentDelta(_, _):
                            break
                        case .cliToolUse(let id, let name, let arguments, let serverName):
                            // Flush any pending text before adding tool call
                            flushStreamBuffer()
                            // Append CLI tool call to the message in real-time for live display
                            appendCLIToolCall(
                                ChatMessage.ToolCall(
                                    id: id,
                                    name: name,
                                    arguments: arguments,
                                    serverName: serverName,
                                    thoughtSignature: nil
                                ),
                                to: assistantID, in: threadID
                            )
                        case .done:
                            flushStreamBuffer()
                        }
                    }
                }

                // Update token usage from API response if available
                if let usage = result.usage {
                    await MainActor.run {
                        if let threadIdx = threads.firstIndex(where: { $0.id == threadID }) {
                            let contextWindow = model.contextWindow
                            if var tokenUsage = threads[threadIdx].tokenUsage {
                                tokenUsage.updateActual(usage)
                                threads[threadIdx].tokenUsage = tokenUsage
                            } else {
                                threads[threadIdx].tokenUsage = ThreadTokenUsage(
                                    estimatedTokens: usage.totalTokens,
                                    actualTokens: usage.totalTokens,
                                    contextWindow: contextWindow
                                )
                            }
                        }
                    }
                }

                // Check if there are tool calls to execute
                if !result.toolCalls.isEmpty {
                    // Update the assistant message with tool call info
                    guard let threadIdx = threads.firstIndex(where: { $0.id == threadID }),
                        let msgIdx = threads[threadIdx].messages.firstIndex(where: {
                            $0.id == assistantID
                        })
                    else {
                        return
                    }

                    if isCLIProvider {
                        // CLI providers (Claude Code, Codex) handle tools internally.
                        // Store tool calls on the message for display only — do NOT execute them.
                        let resolvedToolCalls = result.toolCalls.map { tc -> ChatMessage.ToolCall in
                            ChatMessage.ToolCall(
                                id: tc.id,
                                name: tc.name,
                                arguments: tc.arguments,
                                serverName: tc.serverName,
                                thoughtSignature: tc.thoughtSignature
                            )
                        }
                        threads[threadIdx].messages[msgIdx].toolCalls = resolvedToolCalls
                        // Done — no tool execution, no loop continuation
                        return
                    }

                    // Detect repeated identical tool calls to prevent infinite loops
                    let currentSignature = result.toolCalls.map { "\($0.name):\($0.arguments)" }
                        .joined(separator: "|")
                    if currentSignature == previousToolCallSignature {
                        if messageText(for: assistantID, in: threadID).trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty {
                            setMessageText(
                                "The model repeated the same tool call. Stopping to prevent a loop.",
                                for: assistantID, in: threadID)
                        }
                        return
                    }
                    previousToolCallSignature = currentSignature

                    // Map tool call server names from tool registry
                    let resolvedToolCalls = result.toolCalls.map { tc -> ChatMessage.ToolCall in
                        let serverName =
                            availableTools.first(where: { $0.name == tc.name })?.serverName ?? ""
                        return ChatMessage.ToolCall(
                            id: tc.id,
                            name: tc.name,
                            arguments: tc.arguments,
                            serverName: serverName,
                            thoughtSignature: tc.thoughtSignature
                        )
                    }
                    threads[threadIdx].messages[msgIdx].toolCalls = resolvedToolCalls

                    // Execute each tool call and add results to the thread
                    for tc in resolvedToolCalls {
                        let toolResultText: String

                        // Parse arguments
                        let args: [String: Any]
                        if let data = tc.arguments.data(using: .utf8),
                            let dict = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any]
                        {
                            args = dict
                        } else {
                            args = [:]
                        }

                        if AgentTools.isBuiltIn(serverName: tc.serverName) {
                            // Built-in agent tool
                            let isDangerous = AgentTools.isDestructive(tc.name)
                            let isDangerousMode =
                                isAgent
                                && threads[threads.firstIndex(where: { $0.id == threadID })!]
                                    .dangerousMode

                            if isDangerous && !isDangerousMode {
                                // Normal mode: destructive tool — ask for user confirmation
                                let approved = await withCheckedContinuation {
                                    (continuation: CheckedContinuation<Bool, Never>) in
                                    pendingToolConfirmation = PendingToolConfirmation(
                                        toolName: tc.name,
                                        arguments: args,
                                        displaySummary: PendingToolConfirmation.summary(
                                            toolName: tc.name, arguments: args),
                                        continuation: continuation,
                                        workingDirectory: workDir
                                    )
                                }

                                if approved {
                                    // Snapshot before execution for undo
                                    let undoEntry = captureBeforeState(
                                        toolName: tc.name, arguments: args, workDir: workDir ?? ".")
                                    do {
                                        toolResultText = try await agentToolExecutor.execute(
                                            toolName: tc.name,
                                            arguments: args,
                                            workingDirectory: workDir ?? "."
                                        )
                                        // Finalize undo entry with the new content
                                        if let entry = finalizeUndoEntry(
                                            undoEntry, toolName: tc.name, arguments: args,
                                            workDir: workDir ?? ".")
                                        {
                                            undoHistoryByThread[threadID, default: []].append(entry)
                                        }
                                    } catch {
                                        toolResultText = "Error: \(error.localizedDescription)"
                                    }
                                } else {
                                    toolResultText = "User denied this operation."
                                }
                            } else if isDangerous && isDangerousMode {
                                // Dangerous mode: auto-approve, but capture undo state
                                let undoEntry = captureBeforeState(
                                    toolName: tc.name, arguments: args, workDir: workDir ?? ".")
                                do {
                                    toolResultText = try await agentToolExecutor.execute(
                                        toolName: tc.name,
                                        arguments: args,
                                        workingDirectory: workDir ?? "."
                                    )
                                    if let entry = finalizeUndoEntry(
                                        undoEntry, toolName: tc.name, arguments: args,
                                        workDir: workDir ?? ".")
                                    {
                                        undoHistoryByThread[threadID, default: []].append(entry)
                                    }
                                } catch {
                                    toolResultText = "Error: \(error.localizedDescription)"
                                }
                            } else {
                                // Non-destructive tool — auto-execute
                                do {
                                    toolResultText = try await agentToolExecutor.execute(
                                        toolName: tc.name,
                                        arguments: args,
                                        workingDirectory: workDir ?? "."
                                    )
                                } catch {
                                    toolResultText = "Error: \(error.localizedDescription)"
                                }
                            }
                        } else {
                            // MCP tool — existing path
                            do {
                                let mcpResult = try await mcpManager.callTool(
                                    serverName: tc.serverName,
                                    toolName: tc.name,
                                    arguments: args
                                )
                                toolResultText = mcpResult.content
                                    .compactMap { $0.text }
                                    .joined(separator: "\n")
                            } catch {
                                toolResultText =
                                    "Error executing tool: \(error.localizedDescription)"
                            }
                        }

                        // Add tool result message to thread
                        guard let tIdx = threads.firstIndex(where: { $0.id == threadID }) else {
                            return
                        }
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
                        "\(messageText(for: assistantID, in: threadID))\n\n\(text)",
                        for: assistantID,
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
        // Trigger scroll update when streaming text changes
        lastStreamUpdate = Date()
    }

    /// Append a CLI tool call to a message's toolCalls array during streaming.
    /// This allows tool call chips to appear in real-time as the CLI provider executes them.
    private func appendCLIToolCall(
        _ toolCall: ChatMessage.ToolCall, to messageID: UUID, in threadID: UUID
    ) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
            let messageIndex = threads[threadIndex].messages.firstIndex(where: {
                $0.id == messageID
            })
        else {
            return
        }
        if threads[threadIndex].messages[messageIndex].toolCalls == nil {
            threads[threadIndex].messages[messageIndex].toolCalls = []
        }
        threads[threadIndex].messages[messageIndex].toolCalls?.append(toolCall)
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

    // MARK: - Streaming Buffer Management

    /// Buffers a streaming delta and schedules a flush to batch UI updates.
    /// This reduces per-token lag by updating state every 50ms instead of per token.
    private func bufferStreamDelta(_ delta: String, to messageID: UUID, in threadID: UUID) {
        // If buffer is for a different message/thread, flush immediately first
        if streamBufferMessageID != messageID || streamBufferThreadID != threadID {
            flushStreamBuffer()
            streamBufferMessageID = messageID
            streamBufferThreadID = threadID
        }

        streamBuffer.append(delta)

        // Cancel existing flush timer
        streamFlushWorkItem?.cancel()

        // Schedule flush in 50ms
        let workItem = DispatchWorkItem { [self] in
            flushStreamBuffer()
        }
        streamFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    /// Flushes the accumulated stream buffer to the message.
    /// Call this when streaming ends or when switching messages.
    private func flushStreamBuffer() {
        guard !streamBuffer.isEmpty,
            let messageID = streamBufferMessageID,
            let threadID = streamBufferThreadID
        else {
            return
        }

        appendStreamDelta(streamBuffer, to: messageID, in: threadID)
        streamBuffer = ""
    }

    /// Clears the stream buffer without applying it (used for cleanup).
    private func clearStreamBuffer() {
        streamBuffer = ""
        streamBufferMessageID = nil
        streamBufferThreadID = nil
        streamFlushWorkItem?.cancel()
        streamFlushWorkItem = nil
    }

    // MARK: - Scroll Throttling

    /// Throttles scrollTo calls to ~30fps and respects user scroll position.
    /// Only auto-scrolls if auto-scroll is enabled and user is at bottom.
    /// If auto-scroll is disabled, user must scroll manually.
    /// If user scrolled up while auto-scroll is enabled, shows "New Messages" indicator.
    private func throttledScrollToLast(proxy: ScrollViewProxy) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollTime) >= scrollThrottleInterval else { return }
        lastScrollTime = now

        // Don't auto-scroll if disabled in settings
        guard isAutoScrollEnabled else {
            return
        }

        // Don't auto-scroll if user is reading older messages
        guard !isUserScrolledUp else {
            // Mark that there are unread messages while scrolled up
            hasUnreadMessages = true
            return
        }

        if let lastID = currentMessages.last?.id {
            // Use minimal animation during streaming for better performance
            if streamingMessageID != nil {
                proxy.scrollTo(lastID, anchor: .bottom)
            } else {
                withAnimation {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Tool Confirmation Overlay

    @ViewBuilder
    private func toolConfirmationOverlay(_ confirmation: PendingToolConfirmation) -> some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: confirmationIcon(for: confirmation.toolName))
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)

                    Text(confirmationTitle(for: confirmation))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    // File path badge
                    if let path = confirmation.filePath {
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                theme.divider.frame(height: 1)

                // Content area — varies by tool type
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch confirmation.toolName {
                        case "edit_file":
                            editFileDiffView(confirmation)
                        case "write_file":
                            writeFilePreview(confirmation)
                        case "run_command":
                            runCommandPreview(confirmation)
                        default:
                            // Fallback
                            Text(confirmation.displaySummary)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: 360)

                theme.divider.frame(height: 1)

                // Action buttons
                HStack(spacing: 10) {
                    // Keyboard hint
                    Text("Esc to deny, Return to allow")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)

                    Spacer()

                    Button {
                        let cont = confirmation.continuation
                        pendingToolConfirmation = nil
                        cont.resume(returning: false)
                    } label: {
                        Text("Deny")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(
                                theme.composerBackground, in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.composerBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])

                    Button {
                        let cont = confirmation.continuation
                        pendingToolConfirmation = nil
                        cont.resume(returning: true)
                    } label: {
                        Text("Allow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(width: 560)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.composerBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        }
    }

    // MARK: - Confirmation: edit_file diff view

    @ViewBuilder
    private func editFileDiffView(_ confirmation: PendingToolConfirmation) -> some View {
        let oldText = confirmation.oldText ?? ""
        let newText = confirmation.newText ?? ""
        let oldLines = oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: 0) {
            // Diff header
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red.opacity(0.8))
                    Text("\(oldLines.count) line\(oldLines.count == 1 ? "" : "s") removed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.green.opacity(0.8))
                    Text("\(newLines.count) line\(newLines.count == 1 ? "" : "s") added")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green.opacity(0.8))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Removed lines
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(oldLines.prefix(20).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Text("- ")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.red.opacity(0.7))
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                }
                if oldLines.count > 20 {
                    Text("  ... +\(oldLines.count - 20) more lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 8)

            // Separator
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // Added lines
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(newLines.prefix(20).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Text("+ ")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.7))
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                }
                if newLines.count > 20 {
                    Text("  ... +\(newLines.count - 20) more lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Confirmation: write_file preview

    @ViewBuilder
    private func writeFilePreview(_ confirmation: PendingToolConfirmation) -> some View {
        let content = confirmation.fileContent ?? ""
        let lines = content.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: 0) {
            // Info bar
            HStack(spacing: 8) {
                Image(systemName: confirmation.isNewFile ? "doc.badge.plus" : "doc.badge.arrow.up")
                    .font(.system(size: 11))
                    .foregroundStyle(confirmation.isNewFile ? Color.green.opacity(0.8) : .orange)
                Text(confirmation.isNewFile ? "New file" : "Overwrite existing file")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(confirmation.isNewFile ? Color.green.opacity(0.8) : .orange)
                Spacer()
                Text("\(lines.count) lines, \(formatBytes(content.utf8.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // File content preview
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.prefix(25).enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 32, alignment: .trailing)
                            .padding(.trailing, 8)
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if lines.count > 25 {
                    Text("  ... +\(lines.count - 25) more lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.leading, 40)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.codeBorder, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Confirmation: run_command preview

    @ViewBuilder
    private func runCommandPreview(_ confirmation: PendingToolConfirmation) -> some View {
        let command = confirmation.command ?? ""

        VStack(alignment: .leading, spacing: 0) {
            // Working directory
            if let workDir = threads[selectedThreadIndex ?? 0].workingDirectory {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    Text(abbreviatePathForToast(workDir))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Command
            HStack(alignment: .top, spacing: 8) {
                Text("$")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.7))
                Text(command)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Warning for potentially dangerous commands
            if commandLooksDangerous(command) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("This command may modify or delete files")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func commandLooksDangerous(_ command: String) -> Bool {
        let dangerous = [
            "rm ", "rm\t", "rmdir", "sudo", "chmod", "chown", "mv ", "dd ",
            "> /", ">> /", "| sudo", "curl | sh", "curl | bash",
            "format", "mkfs", "kill ", "killall", "pkill",
        ]
        let lower = command.lowercased()
        return dangerous.contains { lower.contains($0) }
    }

    private func confirmationTitle(for confirmation: PendingToolConfirmation) -> String {
        switch confirmation.toolName {
        case "edit_file": return "Edit File"
        case "write_file": return confirmation.isNewFile ? "Create File" : "Overwrite File"
        case "run_command": return "Run Command"
        default: return "Confirm Action"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return "\(bytes / 1024) KB"
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func confirmationIcon(for toolName: String) -> String {
        switch toolName {
        case "write_file": return "doc.badge.plus"
        case "edit_file": return "pencil.line"
        case "run_command": return "terminal"
        default: return "exclamationmark.triangle"
        }
    }

    // MARK: - Dangerous Mode: Undo Tracking

    /// Captures the state of a file before a destructive tool modifies it.
    /// Returns a partial tuple that will be finalized after execution.
    private func captureBeforeState(toolName: String, arguments: [String: Any], workDir: String)
        -> (filePath: String, fullPath: String, previousContent: String?)?
    {
        guard let path = arguments["path"] as? String else {
            // run_command doesn't have a single file path — skip undo for commands
            return nil
        }

        let fullPath: String
        if path.hasPrefix("/") {
            fullPath = path
        } else {
            fullPath = (workDir as NSString).appendingPathComponent(path)
        }

        let previousContent: String?
        if FileManager.default.fileExists(atPath: fullPath) {
            previousContent = try? String(contentsOfFile: fullPath, encoding: .utf8)
        } else {
            previousContent = nil
        }

        return (filePath: path, fullPath: fullPath, previousContent: previousContent)
    }

    /// Reads the file after execution and creates a finalized UndoEntry.
    private func finalizeUndoEntry(
        _ before: (filePath: String, fullPath: String, previousContent: String?)?, toolName: String,
        arguments: [String: Any], workDir: String
    ) -> UndoEntry? {
        guard let before = before else { return nil }

        let newContent: String
        if let content = try? String(contentsOfFile: before.fullPath, encoding: .utf8) {
            newContent = content
        } else {
            newContent = "(binary or unreadable)"
        }

        let summary: String
        switch toolName {
        case "write_file":
            if before.previousContent == nil {
                summary = "Created \(before.filePath)"
            } else {
                summary = "Overwrote \(before.filePath)"
            }
        case "edit_file":
            let oldText = arguments["old_text"] as? String ?? ""
            let newText = arguments["new_text"] as? String ?? ""
            let oldLines = oldText.components(separatedBy: "\n").count
            let newLines = newText.components(separatedBy: "\n").count
            summary = "Edited \(before.filePath): \(oldLines) -> \(newLines) lines"
        default:
            summary = "\(toolName) on \(before.filePath)"
        }

        return UndoEntry(
            timestamp: .now,
            toolName: toolName,
            filePath: before.filePath,
            fullPath: before.fullPath,
            previousContent: before.previousContent,
            newContent: newContent,
            summary: summary
        )
    }

    // MARK: - Undo Panel Overlay

    @ViewBuilder
    private var undoPanelOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isShowingUndoPanel = false
                }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.accent)

                    Text("Change History")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    let activeCount = undoHistory.filter { !$0.isReverted }.count
                    if activeCount > 0 {
                        Text("\(activeCount) change\(activeCount == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }

                    Button {
                        isShowingUndoPanel = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                theme.divider.frame(height: 1)

                if undoHistory.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(theme.textTertiary)
                        Text("No changes yet")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                        Text("File changes made in dangerous mode will appear here")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxHeight: 200)
                } else {
                    // Change list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(undoHistory.reversed().enumerated()), id: \.element.id) {
                                _, entry in
                                undoEntryRow(entry)

                                theme.divider
                                    .frame(height: 1)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }

                theme.divider.frame(height: 1)

                // Footer actions
                HStack(spacing: 10) {
                    let revertableCount = undoHistory.filter { !$0.isReverted }.count

                    Button {
                        revertAllChanges()
                    } label: {
                        Text("Revert All (\(revertableCount))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(revertableCount > 0 ? Color.red : theme.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                revertableCount > 0
                                    ? Color.red.opacity(0.1) : theme.composerBackground,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        revertableCount > 0
                                            ? Color.red.opacity(0.3) : theme.composerBorder,
                                        lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(revertableCount == 0)

                    Spacer()

                    Button {
                        if let id = selectedThreadID {
                            undoHistoryByThread[id] = nil
                        }
                        isShowingUndoPanel = false
                    } label: {
                        Text("Clear History")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                theme.composerBackground, in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.composerBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingUndoPanel = false
                    } label: {
                        Text("Done")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(width: 560)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.composerBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        }
    }

    private func undoEntryRow(_ entry: UndoEntry) -> some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: undoEntryIcon(entry))
                .font(.system(size: 12))
                .foregroundStyle(entry.isReverted ? theme.textTertiary : undoEntryColor(entry))
                .frame(width: 20)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(entry.isReverted ? theme.textTertiary : theme.textPrimary)
                    .strikethrough(entry.isReverted)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(entry.filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Revert button
            if !entry.isReverted {
                Button {
                    revertEntry(entry)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                        Text("Revert")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Text("Reverted")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func undoEntryIcon(_ entry: UndoEntry) -> String {
        switch entry.toolName {
        case "write_file":
            return entry.previousContent == nil ? "doc.badge.plus" : "doc.badge.arrow.up"
        case "edit_file":
            return "pencil.line"
        default:
            return "terminal"
        }
    }

    private func undoEntryColor(_ entry: UndoEntry) -> Color {
        switch entry.toolName {
        case "write_file":
            return entry.previousContent == nil ? .green : .orange
        case "edit_file":
            return .blue
        default:
            return .purple
        }
    }

    private func revertEntry(_ entry: UndoEntry) {
        guard let threadID = selectedThreadID,
            var entries = undoHistoryByThread[threadID],
            let index = entries.firstIndex(where: { $0.id == entry.id })
        else { return }
        do {
            try entry.revert()
            entries[index].isReverted = true
            undoHistoryByThread[threadID] = entries
            toastManager.show(.success("Reverted: \(entry.summary)", icon: "arrow.uturn.backward"))
        } catch {
            toastManager.show(.error("Failed to revert: \(error.localizedDescription)"))
        }
    }

    private func revertAllChanges() {
        guard let threadID = selectedThreadID,
            var entries = undoHistoryByThread[threadID]
        else { return }
        var revertedCount = 0
        var failedCount = 0

        // Revert in reverse order (newest first)
        for index in entries.indices.reversed() {
            guard !entries[index].isReverted else { continue }
            do {
                try entries[index].revert()
                entries[index].isReverted = true
                revertedCount += 1
            } catch {
                failedCount += 1
            }
        }

        undoHistoryByThread[threadID] = entries

        if failedCount == 0 {
            toastManager.show(
                .success(
                    "Reverted \(revertedCount) change\(revertedCount == 1 ? "" : "s")",
                    icon: "arrow.uturn.backward"))
        } else {
            toastManager.show(.error("Reverted \(revertedCount), failed \(failedCount)"))
        }
    }

    // MARK: - Message Row Helper

    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        let lastAssistantID = currentMessages.last(where: { $0.role == .assistant })?.id
        let isLastAssistant = message.role == .assistant && message.id == lastAssistantID
        MessageRow(
            message: message,
            isStreaming: message.id == streamingMessageID,
            isLastAssistant: isLastAssistant && !isSending
        ) {
            retryLastResponse()
        }
    }
}

// MARK: - Scroll Offset Preference Key

/// Preference key for tracking scroll offset in ScrollView
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Helper view for displaying labeled information in the right sidebar
struct InfoRow: View {
    let label: String
    let value: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
        }
    }
}
