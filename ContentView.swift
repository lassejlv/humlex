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
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.appTheme) private var theme

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
                                Button(role: .destructive) {
                                    threads.removeAll { $0.id == thread.id }
                                    if selectedThreadID == thread.id {
                                        selectedThreadID = threads.first?.id
                                    }
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
        }
        .onDisappear {
            stopStreaming()
        }
        .onChange(of: openAIAPIKey) { _, newValue in
            persistAPIKeyToKeychain(newValue, for: .openAI)
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

    private func adapter(for provider: AIProvider) -> any LLMProviderAdapter {
        switch provider {
        case .openAI:
            return OpenAIAdapter()
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

        let history = threads[idx].messages.map { message in
            LLMChatMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.text,
                attachments: message.attachments
            )
        }
        let assistantID = UUID()
        threads[idx].messages.append(
            ChatMessage(id: assistantID, role: .assistant, text: "", timestamp: .now)
        )
        streamingMessageID = assistantID
        defer {
            isSending = false
            streamingMessageID = nil
            persistChats(threads)
        }

        do {
            try await adapter(for: selectedModel.provider).streamMessage(
                history: history,
                modelID: selectedModel.modelID,
                apiKey: key
            ) { delta in
                await MainActor.run {
                    appendStreamDelta(delta, to: assistantID, in: threadID)
                }
            }

            if messageText(for: assistantID, in: threadID).trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                setMessageText("No response from model.", for: assistantID, in: threadID)
                statusMessage = "The model returned an empty response."
            }
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
        }
    }

    private func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func loadAPIKeysFromKeychain() {
        do {
            if let keyFromKeychain = try KeychainStore.loadString(for: AIProvider.openAI.keychainAccount) {
                openAIAPIKey = keyFromKeychain
            } else {
                let legacyKey = UserDefaults.standard.string(forKey: AIProvider.openAI.keychainAccount) ?? ""
                let trimmedLegacyKey = legacyKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLegacyKey.isEmpty {
                    openAIAPIKey = trimmedLegacyKey
                    try KeychainStore.saveString(trimmedLegacyKey, for: AIProvider.openAI.keychainAccount)
                    UserDefaults.standard.removeObject(forKey: AIProvider.openAI.keychainAccount)
                }
            }

            if let keyFromKeychain = try KeychainStore.loadString(for: AIProvider.openRouter.keychainAccount) {
                openRouterAPIKey = keyFromKeychain
            }

            if let keyFromKeychain = try KeychainStore.loadString(for: AIProvider.vercelAI.keychainAccount) {
                vercelAIAPIKey = keyFromKeychain
            }

            if let keyFromKeychain = try KeychainStore.loadString(for: AIProvider.gemini.keychainAccount) {
                geminiAPIKey = keyFromKeychain
            }
        } catch {
            statusMessage = "Failed loading API key from Keychain: \(error.localizedDescription)"
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

        let history = threads[idx].messages.map { message in
            LLMChatMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.text,
                attachments: message.attachments
            )
        }
        let assistantID = UUID()
        threads[idx].messages.append(
            ChatMessage(id: assistantID, role: .assistant, text: "", timestamp: .now)
        )
        streamingMessageID = assistantID
        defer {
            isSending = false
            streamingMessageID = nil
            persistChats(threads)
        }

        do {
            try await adapter(for: selectedModel.provider).streamMessage(
                history: history,
                modelID: selectedModel.modelID,
                apiKey: key
            ) { delta in
                await MainActor.run {
                    appendStreamDelta(delta, to: assistantID, in: threadID)
                }
            }

            if messageText(for: assistantID, in: threadID).trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                setMessageText("No response from model.", for: assistantID, in: threadID)
                statusMessage = "The model returned an empty response."
            }
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
        }
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

struct ModelPickerPopover: View {
    let models: [LLMModel]
    @Binding var selectedModelReference: String
    @Binding var searchText: String
    @Binding var isPresented: Bool

    @Environment(\.appTheme) private var theme

    private var filteredModels: [LLMModel] {
        if searchText.isEmpty { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.modelID.localizedCaseInsensitiveContains(searchText) ||
            $0.provider.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            theme.divider.frame(height: 1)
            modelList
        }
        .frame(width: 320, height: 400)
        .background(theme.surfaceBackground)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textSecondary)
                .font(.system(size: 12))
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filteredModels.isEmpty {
                    Text("No models found")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .padding(12)
                } else {
                    ForEach(AIProvider.allCases) { provider in
                        providerSection(provider)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: AIProvider) -> some View {
        let providerModels = filteredModels.filter { $0.provider == provider }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if !providerModels.isEmpty {
            HStack(spacing: 6) {
                ProviderIcon(slug: provider.iconSlug, size: 14)
                    .foregroundStyle(theme.textSecondary)
                Text(provider.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(providerModels) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: LLMModel) -> some View {
        let isSelected = model.reference == selectedModelReference
        return Button {
            selectedModelReference = model.reference
            isPresented = false
            searchText = ""
        } label: {
            HStack(spacing: 8) {
                if let slug = modelIconSlug(for: model.modelID) {
                    ProviderIcon(slug: slug, size: 14)
                        .foregroundStyle(theme.textSecondary)
                }
                Text(model.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? theme.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

struct ThreadRow: View {
    let thread: ChatThread
    let isSelected: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thread.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            if let lastMessage = thread.messages.last {
                Text(lastMessage.text)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
