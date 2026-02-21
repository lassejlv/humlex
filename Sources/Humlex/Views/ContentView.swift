//
//  ContentView.swift
//  AI Chat
//
//  Created by Lasse Vestergaard on 10/02/2026.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum SidebarGroup: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case older = "Older"
    }

    private enum ChatImportMode {
        case merge
        case replace
    }

    @AppStorage("selected_model_reference") private var selectedModelReference: String = ""
    @AppStorage("selected_thread_id") private var selectedThreadIDRaw: String = ""
    @AppStorage("provider_ollama_enabled") private var isOllamaEnabled = true
    @AppStorage("auto_scroll_enabled") private var isAutoScrollEnabled = true
    @AppStorage("performance_mode_enabled") private var isPerformanceModeEnabled = true
    @AppStorage("default_system_instructions") private var defaultSystemInstructions: String = ""
    @AppStorage("pinned_thread_ids") private var pinnedThreadIDsRaw: String = ""
    @AppStorage("performance_visible_message_limit") private var performanceVisibleMessageLimit =
        250
    @AppStorage("debug_mode_enabled") private var isDebugModeEnabled = false
    @AppStorage("has_seen_onboarding_v1") private var hasSeenOnboarding = false

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
    @State private var searchRefreshWorkItem: DispatchWorkItem?
    @State private var filteredThreadIDs: [UUID] = []

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
    @AppStorage("openai_compatible_profiles_json") private var openAICompatibleProfilesJSON:
        String =
            "[]"
    @AppStorage("openai_compatible_known_ids") private var openAICompatibleKnownIDsCSV: String = ""
    @AppStorage("openai_compatible_base_url") private var legacyOpenAICompatibleBaseURL: String = ""
    @State private var openAICompatibleProfiles: [OpenAICompatibleProfile] = []
    @State private var openAICompatibleTokens: [String: String] = [:]
    @State private var anthropicAPIKey: String = ""
    @State private var openRouterAPIKey: String = ""
    @State private var fastRouterAPIKey: String = ""
    @State private var vercelAIAPIKey: String = ""
    @State private var geminiAPIKey: String = ""
    @State private var kimiAPIKey: String = ""
    @State private var didLoadAPIKeys = false
    @State private var canMigrateLegacyKeys = false
    @State private var isShowingSettings = false
    @State private var streamingMessageID: UUID?
    @State private var persistWorkItem: DispatchWorkItem?
    @State private var streamingTask: Task<Void, Never>?
    @State private var persistedThreadFingerprintByID: [UUID: Int] = [:]
    @State private var tokenEstimateRefreshWorkItem: DispatchWorkItem?
    @State private var tokenEstimateFingerprintByThread: [UUID: Int] = [:]
    @State private var estimatedTokensByThread: [UUID: Int] = [:]
    @State private var isShowingOnboarding = false

    // MARK: - Streaming Batching
    /// Buffers streaming text deltas to batch UI updates (reduces per-token lag)
    @State private var streamBuffer: String = ""
    @State private var streamBufferMessageID: UUID?
    @State private var streamBufferThreadID: UUID?
    @State private var streamFlushWorkItem: DispatchWorkItem?
    private let streamFlushInterval: TimeInterval = 0.028

    // MARK: - Large Chat Rendering
    /// Per-thread cap for rendered messages to keep long chats responsive.
    @State private var messageRenderLimitByThread: [UUID: Int] = [:]
    private let messageRenderIncrement: Int = 200

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
    @State private var agentToolExecutor = AgentToolExecutor()
    @State private var pendingToolConfirmation: PendingToolConfirmation?
    @State private var isShowingAgentDirectoryPicker = false
    @State private var undoHistoryByThread: [UUID: [UndoEntry]] = [:]
    @State private var isShowingUndoPanel = false
    @State private var isShowingDeleteAllChatsAlert = false
    @State private var isShowingCommandPalette = false
    @State private var commandPaletteMonitor: Any?

    // MARK: - Terminal Panel
    @State private var isTerminalExpanded = false
    @ExperimentalFeature(.terminalPanel) private var isTerminalPanelEnabled

    @StateObject private var mcpManager = MCPManager.shared
    @StateObject private var debugPerformanceMonitor = DebugPerformanceMonitor()
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appUpdater: AppUpdater
    @EnvironmentObject private var statusUpdates: StatusUpdateSDK
    @Environment(\.appTheme) private var theme
    @Environment(\.toastManager) private var toastManager

    private let assistantSafetyBaselinePrompt =
        """
        You are Humlex, a helpful and professional AI assistant.
        Keep responses respectful and avoid sexual, harassing, hateful, or explicit roleplay content.
        If a request is unsafe or inappropriate, decline briefly and redirect to productive help.
        Prioritize accurate, practical, and safe responses.
        """

    private let chatDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var selectedThreadIndex: Int? {
        guard let id = selectedThreadID else { return nil }
        return threads.firstIndex(where: { $0.id == id })
    }

    private var selectedModel: LLMModel? {
        models.first(where: { $0.reference == selectedModelReference })
    }

    private var preferredDefaultModelReference: String {
        guard let preferred = models.sorted(by: isPreferredDefaultModel(_:_:)).first else {
            return selectedModelReference
        }
        return preferred.reference
    }

    private func isPreferredDefaultModel(_ lhs: LLMModel, _ rhs: LLMModel) -> Bool {
        let lhsScore = preferredModelScore(lhs)
        let rhsScore = preferredModelScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }

        let idCompare = lhs.modelID.localizedStandardCompare(rhs.modelID)
        if idCompare != .orderedSame { return idCompare == .orderedDescending }

        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedDescending
    }

    private func preferredModelScore(_ model: LLMModel) -> Int {
        let text = "\(model.modelID) \(model.displayName)".lowercased()
        var score = 0

        if text.contains("latest") { score += 120 }
        if text.contains("preview") { score += 90 }
        if text.contains("thinking") { score += 15 }
        if text.contains("mini") { score -= 8 }

        switch model.provider {
        case .openAI:
            if text.contains("gpt-5") { score += 80 }
            if text.contains("gpt-4.1") || text.contains("gpt-4o") { score += 45 }
            if text.contains("o3") || text.contains("o1") { score += 20 }
        case .anthropic:
            if text.contains("sonnet") { score += 45 }
            if text.contains("opus") { score += 35 }
            if text.contains("haiku") { score -= 10 }
        case .gemini:
            if text.contains("2.5") { score += 55 }
            if text.contains("2.0") { score += 35 }
            if text.contains("1.5") { score += 15 }
            if text.contains("flash") { score += 8 }
        case .openRouter, .fastRouter, .vercelAI, .openAICompatible, .kimi, .ollama:
            break
        }

        return score
    }

    private func isImageGenerationModel(_ model: LLMModel) -> Bool {
        let text = "\(model.modelID) \(model.displayName)".lowercased()
        let blockedTerms = [
            "image",
            "images",
            "dall-e",
            "dalle",
            "gpt-image",
            "recraft",
            "midjourney",
            "stable-diffusion",
            "sdxl",
            "flux",
            "imagen",
        ]
        return blockedTerms.contains(where: { text.contains($0) })
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
        let idSet = Set(filteredThreadIDs)
        return threads.filter { idSet.contains($0.id) }
    }

    private var sortedFilteredThreads: [ChatThread] {
        let orderByID = Dictionary(uniqueKeysWithValues: threads.enumerated().map { ($0.element.id, $0.offset) })
        return filteredThreads.sorted { lhs, rhs in
            let lhsDate = lhs.messages.last?.timestamp ?? .distantFuture
            let rhsDate = rhs.messages.last?.timestamp ?? .distantFuture
            if lhsDate == rhsDate {
                let lhsOrder = orderByID[lhs.id] ?? .max
                let rhsOrder = orderByID[rhs.id] ?? .max
                return lhsOrder < rhsOrder
            }
            return lhsDate > rhsDate
        }
    }

    private var pinnedThreadIDs: Set<UUID> {
        Set(
            pinnedThreadIDsRaw
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        )
    }

    private var pinnedThreads: [ChatThread] {
        sortedFilteredThreads.filter { pinnedThreadIDs.contains($0.id) }
    }

    private var groupedUnpinnedThreads: [(group: SidebarGroup, threads: [ChatThread])] {
        let unpinned = sortedFilteredThreads.filter { !pinnedThreadIDs.contains($0.id) }
        let grouped = Dictionary(grouping: unpinned) { thread in
            sidebarGroup(for: thread)
        }
        return SidebarGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else { return nil }
            return (group: group, threads: items)
        }
    }

    private var currentMessages: [ChatMessage] {
        guard let idx = selectedThreadIndex else { return [] }
        return threads[idx].messages
    }

    /// Message slice currently rendered in the UI (latest N messages for performance).
    private var visibleCurrentMessages: [ChatMessage] {
        guard isPerformanceModeEnabled else { return currentMessages }
        guard let threadID = selectedThreadID else { return currentMessages }
        let limit = messageRenderLimitByThread[threadID] ?? resolvedVisibleMessageLimit
        if currentMessages.count <= limit { return currentMessages }
        return Array(currentMessages.suffix(limit))
    }

    private var hiddenMessageCount: Int {
        max(0, currentMessages.count - visibleCurrentMessages.count)
    }

    private var resolvedVisibleMessageLimit: Int {
        max(100, performanceVisibleMessageLimit)
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
        let contextWindow = selectedModel?.contextWindow ?? 128_000
        let estimatedTokens =
            estimatedTokensByThread[thread.id] ?? thread.tokenUsage?.estimatedTokens
            ?? 0

        if var usage = thread.tokenUsage {
            usage.contextWindow = contextWindow
            if usage.actualTokens == nil { usage.estimatedTokens = estimatedTokens }
            return usage
        }

        return ThreadTokenUsage(estimatedTokens: estimatedTokens, contextWindow: contextWindow)
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

    /// Binding for selected model that also persists model per thread.
    private var selectedModelReferenceBinding: Binding<String> {
        Binding(
            get: { selectedModelReference },
            set: { newValue in
                selectedModelReference = newValue
                guard let idx = selectedThreadIndex else { return }
                threads[idx].modelReference = newValue.isEmpty ? nil : newValue
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
            .sheet(isPresented: $isShowingOnboarding) { onboardingSheet }
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
                applyDefaultSystemPromptToUntitledThreads()

                if let persistedID = UUID(uuidString: selectedThreadIDRaw),
                    threads.contains(where: { $0.id == persistedID })
                {
                    selectedThreadID = persistedID
                }

                if selectedThreadID == nil {
                    selectedThreadID = threads.first?.id
                }

                rebuildFilteredThreadCache()
                refreshTokenEstimate(for: selectedThreadID, immediate: true)

                if models.isEmpty {
                    Task { await fetchModels() }
                }

                Task { await mcpManager.loadAndConnect() }
                appUpdater.startAutomaticChecks(statusUpdates: statusUpdates, interval: 60)

                if isDebugModeEnabled {
                    debugPerformanceMonitor.start()
                }

                if !hasSeenOnboarding {
                    DispatchQueue.main.async {
                        isShowingOnboarding = true
                    }
                }

                // Set up ⌘K shortcut for command palette
                commandPaletteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "k" {
                        if ExperimentalFeatures.isEnabled(.commandPalette) {
                            isShowingCommandPalette.toggle()
                            return nil
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                stopStreaming()
                debugPerformanceMonitor.stop()
                tokenEstimateRefreshWorkItem?.cancel()
                searchRefreshWorkItem?.cancel()
                if let monitor = commandPaletteMonitor {
                    NSEvent.removeMonitor(monitor)
                    commandPaletteMonitor = nil
                }
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
            .onChange(of: fastRouterAPIKey) { _, newValue in
                persistAPIKeyToKeychain(newValue, for: .fastRouter)
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
            .onChange(of: openAICompatibleProfiles) { _, _ in
                persistOpenAICompatibleProfiles()
                syncOpenAICompatibleTokensToKeychain()
            }
            .onChange(of: openAICompatibleTokens) { _, _ in
                syncOpenAICompatibleTokensToKeychain()
            }
            .onChange(of: selectedThreadID) { _, newValue in
                selectedThreadIDRaw = newValue?.uuidString ?? ""
                if let id = newValue, messageRenderLimitByThread[id] == nil {
                    messageRenderLimitByThread[id] = resolvedVisibleMessageLimit
                }
                syncSelectedModelWithCurrentThread()
                refreshTokenEstimate(for: newValue, immediate: true)
            }
            .onChange(of: isPerformanceModeEnabled) { _, newValue in
                guard newValue, let id = selectedThreadID, messageRenderLimitByThread[id] == nil
                else {
                    return
                }
                messageRenderLimitByThread[id] = resolvedVisibleMessageLimit
            }
            .onChange(of: performanceVisibleMessageLimit) { _, _ in
                guard let id = selectedThreadID else { return }
                messageRenderLimitByThread[id] = resolvedVisibleMessageLimit
            }
            .onChange(of: isDebugModeEnabled) { _, newValue in
                if newValue {
                    debugPerformanceMonitor.start()
                } else {
                    debugPerformanceMonitor.stop()
                }
            }
            .onChange(of: threads) { _, newValue in
                schedulePersist(newValue)
                if !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    scheduleFilteredThreadCacheRebuild()
                }
                refreshTokenEstimate(for: selectedThreadID, immediate: false)
            }

        let decorated =
            lifecycle
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
            .overlay(alignment: .topTrailing) {
                if isDebugModeEnabled {
                    DebugPerformanceBanner(monitor: debugPerformanceMonitor)
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                }
            }
            .overlay {
                if ExperimentalFeatures.isEnabled(.commandPalette) && isShowingCommandPalette {
                    CommandPaletteOverlay(
                        isPresented: $isShowingCommandPalette,
                        actions: buildCommandPaletteActions()
                    )
                }
            }
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
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailView
                .frame(minWidth: 400)
                .background(theme.background)
        }
        .background(theme.background)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    createThread()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                }
                .keyboardShortcut("n", modifiers: .command)
                .labelStyle(.iconOnly)
                .help("New Chat")

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                }
                .labelStyle(.iconOnly)
                .help("Settings")
            }
        }
        .tint(theme.accent)
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            sidebarHeader

            if filteredThreads.isEmpty {
                sidebarEmptyState
                    .contextMenu {
                        Button(role: .destructive) {
                            isShowingDeleteAllChatsAlert = true
                        } label: {
                            Label("Delete All Chats", systemImage: "trash.slash")
                        }
                    }
            } else {
                List(selection: $selectedThreadID) {
                    if !pinnedThreads.isEmpty {
                        Section("Pinned") {
                            ForEach(pinnedThreads) { thread in
                                sidebarThreadListRow(thread)
                            }
                        }
                    }

                    ForEach(groupedUnpinnedThreads, id: \.group) { section in
                        Section(section.group.rawValue) {
                            ForEach(section.threads) { thread in
                                sidebarThreadListRow(thread)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(theme.sidebarBackground)
                .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search"))
                .contextMenu {
                    Button(role: .destructive) {
                        isShowingDeleteAllChatsAlert = true
                    } label: {
                        Label("Delete All Chats", systemImage: "trash.slash")
                    }
                }
            }

            AppStatusBarView(
                status: isAppBusy ? nil : statusUpdates.current,
                fallbackText: statusMessage,
                isBusy: isAppBusy,
                busyText: appBusyText
            )
        }
        .background(theme.sidebarBackground)
        .onChange(of: searchText) { _, newValue in
            // Debounce search input by 200ms
            searchDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [self] in
                debouncedSearchText = newValue
                scheduleFilteredThreadCacheRebuild()
            }
            searchDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + searchDebounceInterval, execute: workItem)
        }
    }

    private func sidebarThreadListRow(_ thread: ChatThread) -> some View {
        let isSelected = thread.id == selectedThreadID
        let isPinned = pinnedThreadIDs.contains(thread.id)
        return ThreadRow(thread: thread, isSelected: isSelected, isPinned: isPinned)
            .tag(thread.id as UUID?)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            .contextMenu {
                Button {
                    togglePinnedState(for: thread.id)
                } label: {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }

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

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chats")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Text("\(filteredThreads.count) total")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                createThread()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(theme.hoverBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.chipBorder.opacity(0.8), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("New chat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func togglePinnedState(for threadID: UUID) {
        var ids = pinnedThreadIDs
        if ids.contains(threadID) {
            ids.remove(threadID)
        } else {
            ids.insert(threadID)
        }
        pinnedThreadIDsRaw = ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func sidebarGroup(for thread: ChatThread) -> SidebarGroup {
        guard let lastDate = thread.messages.last?.timestamp else {
            return .today
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(lastDate) { return .today }
        if calendar.isDateInYesterday(lastDate) { return .yesterday }
        if let days = calendar.dateComponents([.day], from: lastDate, to: Date()).day,
            days < 7
        {
            return .thisWeek
        }
        return .older
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(theme.textTertiary)
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No chats yet" : "No matching chats")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Start a conversation to see it here." : "Try a different search term.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(theme.sidebarBackground)
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            detailContent

            // Terminal panel for agent mode
            if isTerminalPanelEnabled,
               let idx = selectedThreadIndex,
               threads[idx].agentEnabled
            {
                TerminalPanelView(
                    isExpanded: $isTerminalExpanded,
                    workingDirectory: threads[idx].workingDirectory
                )
            }

            chatComposerView
        }
        .background(chatCanvasBackground)
    }

    private var chatCanvasBackground: some View {
        Color.clear
    }

    private var isAppBusy: Bool {
        isSending || isLoadingModels || mcpManager.isLoading
    }

    private var appBusyText: String? {
        if isSending {
            let isAgentMode = selectedThreadIndex.map { threads[$0].agentEnabled } ?? false
            return isAgentMode ? "Agent is working..." : "Generating response..."
        }
        if isLoadingModels {
            return "Loading available models..."
        }
        if mcpManager.isLoading {
            return "Connecting MCP servers..."
        }
        return nil
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
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.orange.opacity(0.45),
                                    Color.yellow.opacity(0.15),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 34
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "mug.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(Color.white.opacity(0.9))
                }

                Text("Hello")
                    .font(.system(size: 43, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)

                Text("How can I help you today?")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.textSecondary)

                Text("Default")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.accent.opacity(0.12), in: Capsule())

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 160), spacing: 10),
                        GridItem(.flexible(minimum: 160), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    emptyStateQuickAction(
                        title: "Explain a concept",
                        icon: "lightbulb",
                        prompt: "Explain this concept in simple terms:"
                    )
                    emptyStateQuickAction(
                        title: "Summarize text",
                        icon: "doc.text",
                        prompt: "Summarize this text:"
                    )
                    emptyStateQuickAction(
                        title: "Write code",
                        icon: "chevron.left.forwardslash.chevron.right",
                        prompt: "Help me write code for:"
                    )
                    emptyStateQuickAction(
                        title: "Help me write",
                        icon: "pencil.line",
                        prompt: "Help me write:"
                    )
                }
                .frame(maxWidth: 420)
                .padding(.top, 4)

                if isAppBusy, let busyText = appBusyText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.accent)
                        Text(busyText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.hoverBackground, in: Capsule())
                    .overlay(Capsule().stroke(theme.chipBorder, lineWidth: 1))
                    .padding(.top, 4)
                }

                if statusMessage != nil {
                    Text(statusMessage!)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
        }
    }

    private func emptyStateQuickAction(title: String, icon: String, prompt: String) -> some View {
        Button {
            draft = prompt
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.hoverBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.chipBorder.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                if hiddenMessageCount > 0 {
                    loadEarlierMessagesButton
                }

                let lastAssistantID = currentMessages.last(where: { $0.role == .assistant })?.id
                let indexedMessages = Array(visibleCurrentMessages.enumerated())
                ForEach(indexedMessages, id: \.element.id) { index, message in
                    if shouldHideMergedToolMessage(at: index, in: visibleCurrentMessages) {
                        EmptyView()
                    } else {
                    if shouldShowDateSeparator(at: index, in: visibleCurrentMessages) {
                        dateSeparator(for: message.timestamp)
                    }
                        messageRow(
                            for: message,
                            at: index,
                            in: visibleCurrentMessages,
                            lastAssistantID: lastAssistantID
                        )
                        .id(message.id)
                    }
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

    private var loadEarlierMessagesButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                guard let threadID = selectedThreadID else { return }
                let currentLimit =
                    messageRenderLimitByThread[threadID] ?? resolvedVisibleMessageLimit
                let nextLimit = min(currentMessages.count, currentLimit + messageRenderIncrement)
                messageRenderLimitByThread[threadID] = nextLimit
            } label: {
                Text(
                    "Load \(min(messageRenderIncrement, hiddenMessageCount)) older messages (\(hiddenMessageCount) hidden)"
                )
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func shouldShowDateSeparator(at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index < messages.count else { return false }
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateSeparator(for date: Date) -> some View {
        let calendar = Calendar.current
        let label: String
        if calendar.isDateInToday(date) {
            label = "Today"
        } else if calendar.isDateInYesterday(date) {
            label = "Yesterday"
        } else {
            label = chatDateFormatter.string(from: date)
        }

        return HStack(spacing: 10) {
            Rectangle()
                .fill(theme.divider.opacity(0.5))
                .frame(height: 1)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.hoverBackground.opacity(0.75), in: Capsule())

            Rectangle()
                .fill(theme.divider.opacity(0.5))
                .frame(height: 1)
        }
        .padding(.vertical, 2)
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
            selectedModelReference: selectedModelReferenceBinding,
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

    private var settingsSheet: some View {
        SettingsView(
            openAIAPIKey: $openAIAPIKey,
            openAICompatibleProfiles: $openAICompatibleProfiles,
            openAICompatibleTokens: $openAICompatibleTokens,
            anthropicAPIKey: $anthropicAPIKey,
            openRouterAPIKey: $openRouterAPIKey,
            fastRouterAPIKey: $fastRouterAPIKey,
            vercelAIAPIKey: $vercelAIAPIKey,
            geminiAPIKey: $geminiAPIKey,
            kimiAPIKey: $kimiAPIKey,
            canMigrateLegacyKeys: canMigrateLegacyKeys,
            isLoadingModels: isLoadingModels,
            modelCounts: modelCounts,
            statusMessage: statusMessage,
            currentWorkingDirectory: selectedThreadIndex.flatMap { threads[$0].workingDirectory }
        ) {
            Task { await fetchModels() }
        } onMigrateLegacyKeysToKeychain: {
            migrateLegacyKeysToKeychain()
        } onImportChats: {
            importChatsFromFile()
        } onExportAllChats: {
            exportAllChatsToZip()
        } onDeleteAllChats: {
            clearAllChats(showToast: true)
        } onClose: {
            isShowingSettings = false
        }
    }

    private var onboardingSheet: some View {
        OnboardingView {
            completeOnboarding(openSettings: true)
        } onGetStarted: {
            completeOnboarding(openSettings: false)
        }
    }

    private func createThread() {
        let thread = newThread()
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }

    private func newThread() -> ChatThread {
        let modelReference = preferredDefaultModelReference.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatThread(
            id: UUID(),
            title: "New Chat",
            messages: [],
            systemPrompt: resolvedDefaultSystemPrompt,
            modelReference: modelReference.isEmpty ? nil : modelReference
        )
    }

    private func buildCommandPaletteActions() -> [CommandAction] {
        var actions: [CommandAction] = []

        // Chat actions
        actions.append(CommandAction(
            title: "New Chat",
            subtitle: "Start a new conversation",
            icon: "square.and.pencil",
            shortcut: "⌘N"
        ) {
            createThread()
        })

        actions.append(CommandAction(
            title: "Settings",
            subtitle: "Open app settings",
            icon: "gearshape",
            shortcut: "⌘,"
        ) {
            isShowingSettings = true
        })

        // Thread-specific actions
        if selectedThreadIndex != nil {
            actions.append(CommandAction(
                title: "Clear Current Chat",
                subtitle: "Remove all messages in this chat",
                icon: "trash",
                shortcut: nil
            ) {
                if let idx = selectedThreadIndex {
                    threads[idx].messages = []
                    toastManager.show(.success("Chat cleared", icon: "trash"))
                }
            })

            actions.append(CommandAction(
                title: "Export Chat to Markdown",
                subtitle: "Save this conversation as a .md file",
                icon: "square.and.arrow.up",
                shortcut: nil
            ) {
                if let idx = selectedThreadIndex {
                    exportThreadToMarkdown(threads[idx])
                }
            })

            if let idx = selectedThreadIndex {
                let thread = threads[idx]
                actions.append(CommandAction(
                    title: thread.agentEnabled ? "Disable Agent Mode" : "Enable Agent Mode",
                    subtitle: thread.agentEnabled ? "Turn off file system access" : "Allow file operations",
                    icon: thread.agentEnabled ? "bolt.slash" : "bolt",
                    shortcut: nil
                ) {
                    if thread.agentEnabled {
                        threads[idx].agentEnabled = false
                        threads[idx].workingDirectory = nil
                        toastManager.show(.info("Agent mode disabled"))
                    } else {
                        isShowingAgentDirectoryPicker = true
                    }
                })
            }
        }

        // Model switching
        for model in models.prefix(10) {
            actions.append(CommandAction(
                title: "Switch to \(model.displayName)",
                subtitle: model.provider.rawValue,
                icon: "cpu",
                shortcut: nil
            ) {
                selectedModelReference = model.reference
                toastManager.show(.info("Model: \(model.displayName)"))
            })
        }

        // Theme switching
        for appTheme in themeManager.themes {
            actions.append(CommandAction(
                title: "Theme: \(appTheme.name)",
                subtitle: "Switch appearance theme",
                icon: "paintbrush",
                shortcut: nil
            ) {
                themeManager.select(appTheme)
                toastManager.show(.info("Theme: \(appTheme.name)", icon: "paintbrush"))
            })
        }

        // Data actions
        actions.append(CommandAction(
            title: "Import Chats",
            subtitle: "Load conversations from file",
            icon: "square.and.arrow.down",
            shortcut: nil
        ) {
            importChatsFromFile()
        })

        actions.append(CommandAction(
            title: "Export All Chats",
            subtitle: "Save all conversations to a zip file",
            icon: "archivebox",
            shortcut: nil
        ) {
            exportAllChatsToZip()
        })

        actions.append(CommandAction(
            title: "Refresh Models",
            subtitle: "Fetch available models from providers",
            icon: "arrow.clockwise",
            shortcut: nil
        ) {
            Task { await fetchModels() }
        })

        return actions
    }

    private func completeOnboarding(openSettings: Bool) {
        hasSeenOnboarding = true
        isShowingOnboarding = false

        guard openSettings else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isShowingSettings = true
        }
    }

    private func clearAllChats(showToast: Bool) {
        persistWorkItem?.cancel()
        do {
            try ChatPersistence.wipeAllChats()
        } catch {
            statusMessage = "Failed deleting chat files: \(error.localizedDescription)"
        }
        threads = [newThread()]
        filteredThreadIDs = []
        persistedThreadFingerprintByID = [:]
        tokenEstimateFingerprintByThread = [:]
        estimatedTokensByThread = [:]
        selectedThreadID = threads.first?.id
        refreshTokenEstimate(for: selectedThreadID, immediate: true)
        persistChats(threads)
        if showToast {
            toastManager.show(.success("All chats cleared", icon: "trash"))
        }
    }

    private func exportThreadToMarkdown(_ thread: ChatThread) {
        let markdown = markdown(for: thread)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "\(sanitizedExportName(thread.title, fallback: "chat")).md"
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

    private func importChatsFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        do {
            let importedThreads = try loadThreadsForImport(from: fileURL)
            guard !importedThreads.isEmpty else {
                toastManager.show(.error("No chats found in selected file"))
                return
            }

            guard let mode = chooseImportMode() else { return }
            importChats(importedThreads, mode: mode)
        } catch {
            toastManager.show(.error("Failed to import chats: \(error.localizedDescription)"))
        }
    }

    private func chooseImportMode() -> ChatImportMode? {
        let alert = NSAlert()
        alert.messageText = "Import Chats"
        alert.informativeText = "Choose how imported chats should be applied."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace Existing")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .replace
        default:
            return nil
        }
    }

    private func loadThreadsForImport(from fileURL: URL) throws -> [ChatThread] {
        if fileURL.pathExtension.lowercased() == "zip" {
            return try loadThreadsFromZip(fileURL)
        }
        return try decodeThreadsFromJSON(at: fileURL)
    }

    private func loadThreadsFromZip(_ zipURL: URL) throws -> [ChatThread] {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("humlex-import-\(UUID().uuidString)", isDirectory: true)

        defer { try? fileManager.removeItem(at: tempRoot) }

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, tempRoot.path]
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
            throw NSError(
                domain: "HumlexImport",
                code: Int(unzip.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Could not unzip archive."]
            )
        }

        let jsonURL = try findImportJSON(in: tempRoot)
        return try decodeThreadsFromJSON(at: jsonURL)
    }

    private func findImportJSON(in root: URL) throws -> URL {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var jsonCandidates: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "json" else { continue }
            jsonCandidates.append(url)
        }

        if let preferred = jsonCandidates.first(where: {
            $0.lastPathComponent.lowercased() == "all-chats.json"
        }) {
            return preferred
        }

        if jsonCandidates.count == 1, let only = jsonCandidates.first {
            return only
        }

        throw NSError(
            domain: "HumlexImport",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not find a valid chats JSON file in the zip (expected all-chats.json)."
            ]
        )
    }

    private func decodeThreadsFromJSON(at url: URL) throws -> [ChatThread] {
        let data = try Data(contentsOf: url)

        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601

        if let threads = try? isoDecoder.decode([ChatThread].self, from: data) {
            return threads
        }

        if let thread = try? isoDecoder.decode(ChatThread.self, from: data) {
            return [thread]
        }

        let fallbackDecoder = JSONDecoder()
        if let threads = try? fallbackDecoder.decode([ChatThread].self, from: data) {
            return threads
        }
        if let thread = try? fallbackDecoder.decode(ChatThread.self, from: data) {
            return [thread]
        }

        throw NSError(
            domain: "HumlexImport",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON format for chat import."]
        )
    }

    private func importChats(_ imported: [ChatThread], mode: ChatImportMode) {
        switch mode {
        case .merge:
            mergeImportedThreads(imported)
        case .replace:
            replaceChatsWithImported(imported)
        }
    }

    private func normalizeImportedThreads(_ imported: [ChatThread], existingIDs: Set<UUID>)
        -> [ChatThread]
    {
        var usedIDs = existingIDs
        var mergedImports: [ChatThread] = []

        for thread in imported {
            if usedIDs.insert(thread.id).inserted {
                mergedImports.append(thread)
                continue
            }

            let remapped = ChatThread(
                id: UUID(),
                title: thread.title,
                messages: thread.messages,
                agentEnabled: thread.agentEnabled,
                dangerousMode: thread.dangerousMode,
                workingDirectory: thread.workingDirectory,
                systemPrompt: thread.systemPrompt,
                tokenUsage: thread.tokenUsage,
                modelReference: thread.modelReference
            )
            usedIDs.insert(remapped.id)
            mergedImports.append(remapped)
        }

        return mergedImports
    }

    private func mergeImportedThreads(_ imported: [ChatThread]) {
        let mergedImports = normalizeImportedThreads(imported, existingIDs: Set(threads.map(\.id)))

        guard !mergedImports.isEmpty else {
            toastManager.show(.error("No chats were imported"))
            return
        }

        threads = mergedImports + threads
        selectedThreadID = mergedImports.first?.id ?? selectedThreadID

        tokenEstimateFingerprintByThread = [:]
        estimatedTokensByThread = [:]
        refreshTokenEstimate(for: selectedThreadID, immediate: true)
        persistChats(threads)

        toastManager.show(
            .success("Imported \(mergedImports.count) chat(s)", icon: "square.and.arrow.down")
        )
    }

    private func replaceChatsWithImported(_ imported: [ChatThread]) {
        let normalized = normalizeImportedThreads(imported, existingIDs: [])
        guard !normalized.isEmpty else {
            toastManager.show(.error("No chats were imported"))
            return
        }

        threads = normalized
        selectedThreadID = normalized.first?.id

        filteredThreadIDs = []
        tokenEstimateFingerprintByThread = [:]
        estimatedTokensByThread = [:]
        refreshTokenEstimate(for: selectedThreadID, immediate: true)
        persistChats(threads)

        toastManager.show(
            .success(
                "Replaced with \(normalized.count) imported chat(s)",
                icon: "arrow.triangle.2.circlepath")
        )
    }

    private func exportAllChatsToZip() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "Humlex-Chats-\(formatter.string(from: .now)).zip"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let fileManager = FileManager.default
            let tempRoot = fileManager.temporaryDirectory
                .appendingPathComponent("humlex-export-\(UUID().uuidString)", isDirectory: true)
            let exportRoot = tempRoot.appendingPathComponent("Humlex Chats", isDirectory: true)
            let markdownDir = exportRoot.appendingPathComponent("markdown", isDirectory: true)

            defer { try? fileManager.removeItem(at: tempRoot) }

            try fileManager.createDirectory(at: markdownDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let archiveData = try encoder.encode(threads)
            try archiveData.write(
                to: exportRoot.appendingPathComponent("all-chats.json"),
                options: .atomic
            )

            struct ExportManifest: Codable {
                let exportedAt: Date
                let app: String
                let formatVersion: Int
                let chatCount: Int
            }

            let manifest = ExportManifest(
                exportedAt: .now,
                app: "Humlex",
                formatVersion: 1,
                chatCount: threads.count
            )
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: exportRoot.appendingPathComponent("manifest.json"),
                options: .atomic
            )

            for (index, thread) in threads.enumerated() {
                let fallback = "chat-\(index + 1)"
                let safeTitle = sanitizedExportName(thread.title, fallback: fallback)
                let markdownURL = markdownDir.appendingPathComponent(
                    String(format: "%03d-%@.md", index + 1, safeTitle)
                )
                try markdown(for: thread).write(
                    to: markdownURL,
                    atomically: true,
                    encoding: .utf8
                )
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            let zipProcess = Process()
            zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zipProcess.arguments = [
                "-c", "-k", "--sequesterRsrc", "--keepParent",
                exportRoot.path, destinationURL.path,
            ]
            try zipProcess.run()
            zipProcess.waitUntilExit()

            guard zipProcess.terminationStatus == 0 else {
                throw NSError(
                    domain: "HumlexExport",
                    code: Int(zipProcess.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create zip archive."]
                )
            }

            toastManager.show(
                .success("Exported \(threads.count) chat(s) to zip", icon: "archivebox")
            )
        } catch {
            toastManager.show(.error("Failed to export chats: \(error.localizedDescription)"))
        }
    }

    private func markdown(for thread: ChatThread) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var markdown = "# \(thread.title)\n\n"

        for message in thread.messages {
            let role: String
            switch message.role {
            case .user:
                role = "**User**"
            case .assistant:
                role = "**Assistant**"
            case .tool:
                role = "**Tool** (\(message.toolName ?? "unknown"))"
            }
            let timestamp = dateFormatter.string(from: message.timestamp)
            markdown += "\(role) — _\(timestamp)_\n\n"
            markdown += "\(message.text)\n\n---\n\n"
        }

        return markdown
    }

    private func sanitizedExportName(_ name: String, fallback: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned =
            name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")

        let result = cleaned.isEmpty ? fallback : cleaned
        return String(result.prefix(80))
    }

    private func adapter(for provider: AIProvider) -> any LLMProviderAdapter {
        switch provider {
        case .openAI:
            return OpenAIAdapter()
        case .openAICompatible:
            return OpenAICompatibleAdapter(baseURLString: "")
        case .anthropic:
            return AnthropicAdapter()
        case .openRouter:
            return OpenRouterAdapter()
        case .fastRouter:
            return FastRouterAdapter()
        case .vercelAI:
            return VercelAIAdapter()
        case .gemini:
            return GeminiAdapter()
        case .kimi:
            return KimiAdapter()
        case .ollama:
            return OllamaAdapter()
        }
    }

    private func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .openAI:
            return openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible:
            return ""
        case .anthropic:
            return anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openRouter:
            return openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .fastRouter:
            return fastRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .vercelAI:
            return vercelAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini:
            return geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .kimi:
            return kimiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .ollama:
            return ""
        }
    }

    private func isProviderEnabled(_ provider: AIProvider) -> Bool {
        switch provider {
        case .ollama:
            return isOllamaEnabled
        default:
            return true
        }
    }

    private func loadChatsFromDisk() {
        do {
            if let loaded = try ChatPersistence.load(), !loaded.isEmpty {
                threads = loaded
                persistedThreadFingerprintByID = loaded.reduce(into: [:]) { result, thread in
                    result[thread.id] = threadPersistenceFingerprint(thread)
                }
            }
        } catch {
            statusMessage = "Failed loading chats: \(error.localizedDescription)"
        }
    }

    private func syncSelectedModelWithCurrentThread() {
        guard let idx = selectedThreadIndex else { return }

        let threadModelReference = threads[idx].modelReference ?? ""
        if !threadModelReference.isEmpty,
            models.contains(where: { $0.reference == threadModelReference })
        {
            if selectedModelReference != threadModelReference {
                selectedModelReference = threadModelReference
            }
            return
        }

        let fallback = preferredDefaultModelReference

        if selectedModelReference != fallback {
            selectedModelReference = fallback
        }
        threads[idx].modelReference = fallback.isEmpty ? nil : fallback
    }

    private var resolvedDefaultSystemPrompt: String? {
        let trimmed = defaultSystemInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyDefaultSystemPromptToUntitledThreads() {
        guard let defaultPrompt = resolvedDefaultSystemPrompt else { return }
        for idx in threads.indices {
            let hasMessages = !threads[idx].messages.isEmpty
            let isUntitled = threads[idx].title == "New Chat"
            let hasPrompt = !(threads[idx].systemPrompt ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            if !hasMessages && isUntitled && !hasPrompt {
                threads[idx].systemPrompt = defaultPrompt
            }
        }
    }

    private func scheduleFilteredThreadCacheRebuild() {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchRefreshWorkItem?.cancel()
            searchRefreshWorkItem = nil
            if !filteredThreadIDs.isEmpty {
                filteredThreadIDs = []
            }
            return
        }

        searchRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [self] in
            rebuildFilteredThreadCache()
        }
        searchRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func rebuildFilteredThreadCache() {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            filteredThreadIDs = []
            return
        }

        filteredThreadIDs = threads.compactMap { thread in
            if thread.title.localizedCaseInsensitiveContains(query) {
                return thread.id
            }
            if thread.messages.contains(where: { $0.text.localizedCaseInsensitiveContains(query) })
            {
                return thread.id
            }
            return nil
        }
    }

    private func refreshTokenEstimate(for threadID: UUID?, immediate: Bool) {
        guard let threadID else { return }

        if immediate {
            tokenEstimateRefreshWorkItem?.cancel()
            tokenEstimateRefreshWorkItem = nil
            refreshTokenEstimateNow(for: threadID)
            return
        }

        guard tokenEstimateRefreshWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [self] in
            tokenEstimateRefreshWorkItem = nil
            refreshTokenEstimateNow(for: threadID)
        }
        tokenEstimateRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func refreshTokenEstimateNow(for threadID: UUID) {
        guard let idx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let messages = threads[idx].messages
        let fingerprint = tokenEstimateFingerprint(for: messages)

        if tokenEstimateFingerprintByThread[threadID] == fingerprint {
            return
        }

        estimatedTokensByThread[threadID] = TokenEstimator.estimateTotalTokens(for: messages)
        tokenEstimateFingerprintByThread[threadID] = fingerprint
    }

    private func tokenEstimateFingerprint(for messages: [ChatMessage]) -> Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        if let last = messages.last {
            hasher.combine(last.id)
            hasher.combine(last.text.count)
            hasher.combine(last.attachments.count)
            hasher.combine(last.toolCalls?.count ?? 0)
        }
        return hasher.finalize()
    }

    private func persistChats(_ threads: [ChatThread]) {
        do {
            var nextFingerprints = persistedThreadFingerprintByID
            let currentIDs = Set(threads.map(\.id))

            for removedID in Set(nextFingerprints.keys).subtracting(currentIDs) {
                try ChatPersistence.deleteThread(id: removedID)
                nextFingerprints.removeValue(forKey: removedID)
            }

            for thread in threads {
                let fingerprint = threadPersistenceFingerprint(thread)
                if nextFingerprints[thread.id] != fingerprint {
                    try ChatPersistence.saveThread(thread)
                    nextFingerprints[thread.id] = fingerprint
                }
            }

            let indexEntries = threads.map { ChatIndexEntry(from: $0) }
            try ChatPersistence.saveIndex(indexEntries)
            persistedThreadFingerprintByID = nextFingerprints
        } catch {
            statusMessage = "Failed saving chats: \(error.localizedDescription)"
        }
    }

    private func threadPersistenceFingerprint(_ thread: ChatThread) -> Int {
        var hasher = Hasher()
        hasher.combine(thread.id)
        hasher.combine(thread.title)
        hasher.combine(thread.agentEnabled)
        hasher.combine(thread.dangerousMode)
        hasher.combine(thread.workingDirectory ?? "")
        hasher.combine(thread.systemPrompt ?? "")
        hasher.combine(thread.modelReference ?? "")

        if let usage = thread.tokenUsage {
            hasher.combine(usage.estimatedTokens)
            hasher.combine(usage.actualTokens ?? -1)
            hasher.combine(usage.contextWindow)
            hasher.combine(usage.lastUpdated.timeIntervalSince1970)
        } else {
            hasher.combine(-1)
        }

        hasher.combine(thread.messages.count)
        if let last = thread.messages.last {
            hasher.combine(last.id)
            hasher.combine(last.role.rawValue)
            hasher.combine(last.text.count)
            hasher.combine(last.attachments.count)
            hasher.combine(last.toolCalls?.count ?? 0)
            hasher.combine(last.toolCallID ?? "")
            hasher.combine(last.toolName ?? "")
            hasher.combine(last.timestamp.timeIntervalSince1970)
        }

        return hasher.finalize()
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

    private func startSend(force: Bool = false) {
        if !force,
            let usage = currentContextUsage,
            usage.isAtRisk
        {
            let alert = NSAlert()
            alert.messageText = "Context Window Almost Full"
            alert.informativeText =
                "This chat is above 90% of the model context limit. Sending may fail or lose older context."
            alert.addButton(withTitle: "Send Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
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
            if let key = try KeychainStore.loadString(for: AIProvider.fastRouter.keychainAccount) {
                fastRouterAPIKey = key
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

            loadOpenAICompatibleProfiles()
            migrateLegacyOpenAICompatibleConfigIfNeeded()
            loadOpenAICompatibleTokensFromKeychain()
            syncOpenAICompatibleTokensToKeychain()
            canMigrateLegacyKeys = try KeychainStore.legacyStoreHasKeysMissingFromKeychain()
        } catch {
            statusMessage = "Failed loading API keys: \(error.localizedDescription)"
        }
    }

    private func migrateLegacyKeysToKeychain() {
        do {
            let result = try KeychainStore.migrateLegacyFileStoreToKeychain(removeLegacyFile: true)
            canMigrateLegacyKeys = try KeychainStore.legacyStoreHasKeysMissingFromKeychain()
            loadAPIKeysFromKeychain()

            if result.migratedKeys > 0 {
                statusMessage =
                    "Migrated \(result.migratedKeys) key(s) to Keychain and removed legacy store."
            } else if result.totalKeys > 0 {
                statusMessage =
                    "No keys migrated (already in Keychain or empty). Legacy store removed."
            } else {
                statusMessage = "No legacy keys found to migrate."
            }
        } catch {
            statusMessage = "Failed migrating legacy keys: \(error.localizedDescription)"
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

    private func openAICompatibleTokenKey(for profileID: String) -> String {
        "openai_compatible_api_key_\(profileID)"
    }

    private func loadOpenAICompatibleProfiles() {
        let data = Data(openAICompatibleProfilesJSON.utf8)
        if let decoded = try? JSONDecoder().decode([OpenAICompatibleProfile].self, from: data) {
            openAICompatibleProfiles = decoded
        } else {
            openAICompatibleProfiles = []
        }
    }

    private func persistOpenAICompatibleProfiles() {
        if let data = try? JSONEncoder().encode(openAICompatibleProfiles),
            let json = String(data: data, encoding: .utf8)
        {
            openAICompatibleProfilesJSON = json
        }
    }

    private func loadOpenAICompatibleTokensFromKeychain() {
        var loaded: [String: String] = [:]
        for profile in openAICompatibleProfiles {
            let maybeToken = try? KeychainStore.loadString(
                for: openAICompatibleTokenKey(for: profile.id))
            if let token = maybeToken ?? nil, !token.isEmpty { loaded[profile.id] = token }
        }
        openAICompatibleTokens = loaded
    }

    private func syncOpenAICompatibleTokensToKeychain() {
        let currentIDs = Set(openAICompatibleProfiles.map(\.id))
        let knownIDs = Set(
            openAICompatibleKnownIDsCSV.split(separator: ",").map { String($0) }.filter {
                !$0.isEmpty
            })

        do {
            for profileID in currentIDs {
                let token = (openAICompatibleTokens[profileID] ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let key = openAICompatibleTokenKey(for: profileID)
                if token.isEmpty {
                    try KeychainStore.deleteValue(for: key)
                } else {
                    try KeychainStore.saveString(token, for: key)
                }
            }

            for removedID in knownIDs.subtracting(currentIDs) {
                try KeychainStore.deleteValue(for: openAICompatibleTokenKey(for: removedID))
            }

            openAICompatibleKnownIDsCSV = currentIDs.sorted().joined(separator: ",")
        } catch {
            statusMessage =
                "Failed saving OpenAI Compatible token to Keychain: \(error.localizedDescription)"
        }
    }

    private func migrateLegacyOpenAICompatibleConfigIfNeeded() {
        guard openAICompatibleProfiles.isEmpty else { return }
        let legacyEndpoint = legacyOpenAICompatibleBaseURL.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let legacyToken =
            (try? KeychainStore.loadString(for: AIProvider.openAICompatible.keychainAccount) ?? "")
            ?? ""
        let trimmedToken = legacyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyEndpoint.isEmpty || !trimmedToken.isEmpty else { return }

        let profile = OpenAICompatibleProfile(name: "OpenAI Compatible", baseURL: legacyEndpoint)
        openAICompatibleProfiles = [profile]
        if !trimmedToken.isEmpty {
            openAICompatibleTokens[profile.id] = trimmedToken
        }
        persistOpenAICompatibleProfiles()

        do {
            try KeychainStore.deleteValue(for: AIProvider.openAICompatible.keychainAccount)
        } catch {
            // ignore migration cleanup failures
        }
    }

    private func openAICompatibleProfileContext(for model: LLMModel) -> (
        profile: OpenAICompatibleProfile, token: String, modelID: String
    )? {
        guard let parsed = parseOpenAICompatibleModelID(model.modelID),
            let profile = openAICompatibleProfiles.first(where: { $0.id == parsed.profileID })
        else {
            return nil
        }
        let token = (openAICompatibleTokens[profile.id] ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        guard !profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (profile, token, parsed.modelID)
    }

    private func encodeOpenAICompatibleModelID(profileID: String, modelID: String) -> String {
        "oac:\(profileID)::\(modelID)"
    }

    private func parseOpenAICompatibleModelID(_ encoded: String) -> (
        profileID: String, modelID: String
    )? {
        guard encoded.hasPrefix("oac:") else { return nil }
        let raw = String(encoded.dropFirst(4))
        guard let separator = raw.range(of: "::") else { return nil }
        let profileID = String(raw[..<separator.lowerBound])
        let modelID = String(raw[separator.upperBound...])
        guard !profileID.isEmpty, !modelID.isEmpty else { return nil }
        return (profileID, modelID)
    }

    @MainActor
    private func fetchModels() async {
        var collected: [LLMModel] = []
        var errors: [String] = []

        isLoadingModels = true
        defer { isLoadingModels = false }

        for provider in AIProvider.allCases {
            guard isProviderEnabled(provider) else { continue }
            if provider == .openAICompatible {
                for profile in openAICompatibleProfiles {
                    let endpoint = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let token = (openAICompatibleTokens[profile.id] ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    guard !endpoint.isEmpty, !token.isEmpty else { continue }

                    do {
                        let adapter = OpenAICompatibleAdapter(baseURLString: endpoint)
                        let providerModels = try await adapter.fetchModels(apiKey: token)
                        let prefixed = providerModels.map { model in
                            LLMModel(
                                provider: .openAICompatible,
                                modelID: encodeOpenAICompatibleModelID(
                                    profileID: profile.id,
                                    modelID: model.modelID
                                ),
                                displayName: "\(profile.name) · \(model.displayName)"
                            )
                        }
                        collected.append(contentsOf: prefixed)
                    } catch {
                        errors.append(
                            "\(provider.rawValue) (\(profile.name)): \(error.localizedDescription)")
                    }
                }
                continue
            }

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

        collected = collected.filter { !isImageGenerationModel($0) }

        collected.sort { lhs, rhs in
            if lhs.provider != rhs.provider {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                == .orderedAscending
        }
        models = collected

        if !models.contains(where: { $0.reference == selectedModelReference }) {
            selectedModelReference = preferredDefaultModelReference
        }
        syncSelectedModelWithCurrentThread()

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
            threads[idx].title = suggestedThreadTitle(from: text, attachments: messageAttachments)
        }

        defer {
            isSending = false
            streamingMessageID = nil
            persistChats(threads)
        }

        if selectedModel.provider == .openAICompatible {
            guard let context = openAICompatibleProfileContext(for: selectedModel) else {
                statusMessage = "Missing OpenAI Compatible profile endpoint or bearer token."
                return
            }
            await performStreamingLoop(
                threadID: threadID,
                threadIndex: idx,
                model: selectedModel,
                apiKey: context.token,
                adapterOverride: OpenAICompatibleAdapter(baseURLString: context.profile.baseURL),
                modelIDOverride: context.modelID
            )
        } else {
            let key = apiKey(for: selectedModel.provider)
            guard !key.isEmpty || !selectedModel.provider.requiresAPIKey else {
                statusMessage = "Missing \(selectedModel.provider.rawValue) API key."
                return
            }
            await performStreamingLoop(
                threadID: threadID,
                threadIndex: idx,
                model: selectedModel,
                apiKey: key
            )
        }
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
        apiKey: String,
        adapterOverride: (any LLMProviderAdapter)? = nil,
        modelIDOverride: String? = nil
    ) async {
        guard let idx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let isAgent = threads[idx].agentEnabled
        let workDir = threads[idx].workingDirectory
        let maxToolIterations = isAgent ? 25 : 5
        var previousToolCallSignature: String? = nil

        // Merge tools: MCP tools + built-in agent tools (if agent mode is on)
        // Always include fetch tool for normal chat mode
        let availableTools: [MCPTool] =
            isAgent
            ? mcpManager.tools + AgentTools.definitions()
            : mcpManager.tools + AgentTools.fetchDefinitions()

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

            systemPromptParts.append(assistantSafetyBaselinePrompt)

            if let configuredPrompt = resolvedSystemPrompt(for: threads[currentIdx]) {
                systemPromptParts.append(configuredPrompt)
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
                let effectiveAdapter = adapterOverride ?? adapter(for: model.provider)
                let effectiveModelID = modelIDOverride ?? model.modelID

                let result = try await effectiveAdapter.streamMessage(
                    history: history,
                    modelID: effectiveModelID,
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
    /// This reduces per-token lag by updating state at ~35fps instead of per token.
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

        // Schedule a short flush interval so streaming feels smooth without overwhelming SwiftUI.
        let workItem = DispatchWorkItem { [self] in
            flushStreamBuffer()
        }
        streamFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + streamFlushInterval, execute: workItem)
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

        withAnimation(.easeOut(duration: 0.08)) {
            appendStreamDelta(streamBuffer, to: messageID, in: threadID)
        }
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

    private func resolvedSystemPrompt(for thread: ChatThread) -> String? {
        let threadPrompt = (thread.systemPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !threadPrompt.isEmpty {
            return threadPrompt
        }
        return resolvedDefaultSystemPrompt
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

    private func suggestedThreadTitle(from text: String, attachments: [Attachment]) -> String {
        let normalizedText = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedText.isEmpty {
            return String(normalizedText.prefix(40))
        }

        if let firstAttachment = attachments.first {
            return String("File: \(firstAttachment.fileName)".prefix(40))
        }

        return "New Chat"
    }

    // MARK: - Message Row Helper

    @ViewBuilder
    private func messageRow(
        for message: ChatMessage,
        at index: Int,
        in messages: [ChatMessage],
        lastAssistantID: UUID?
    ) -> some View {
        let isLastAssistant = message.role == .assistant && message.id == lastAssistantID
        let isAgentModeForThread = selectedThreadIndex.map { threads[$0].agentEnabled } ?? false
        let mergedResults = mergedToolResults(forAssistantAt: index, in: messages)
        MessageRow(
            message: message,
            isStreaming: message.id == streamingMessageID,
            isAgentMode: isAgentModeForThread,
            isLastAssistant: isLastAssistant && !isSending,
            mergedToolResultsByCallID: mergedResults
        ) {
            retryLastResponse()
        }
        .equatable()
    }

    private func mergedToolResults(forAssistantAt index: Int, in messages: [ChatMessage]) -> [String: ChatMessage] {
        guard index < messages.count else { return [:] }
        let assistantMessage = messages[index]
        guard assistantMessage.role == .assistant,
            let toolCalls = assistantMessage.toolCalls,
            !toolCalls.isEmpty
        else {
            return [:]
        }

        let toolCallIDs = Set(toolCalls.map(\.id))
        var results: [String: ChatMessage] = [:]
        var cursor = index + 1
        while cursor < messages.count {
            let candidate = messages[cursor]
            if candidate.role != .tool {
                break
            }
            if let callID = candidate.toolCallID, toolCallIDs.contains(callID) {
                results[callID] = candidate
            }
            cursor += 1
        }
        return results
    }

    private func shouldHideMergedToolMessage(at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index < messages.count else { return false }
        let message = messages[index]
        guard message.role == .tool, let toolCallID = message.toolCallID else { return false }

        var cursor = index - 1
        while cursor >= 0 {
            let previous = messages[cursor]
            if previous.role == .tool {
                cursor -= 1
                continue
            }
            guard previous.role == .assistant,
                let calls = previous.toolCalls,
                calls.contains(where: { $0.id == toolCallID })
            else {
                return false
            }
            return true
        }
        return false
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
