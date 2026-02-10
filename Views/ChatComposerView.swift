import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// A file or folder entry for the @-mention popup.
struct MentionEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String   // path relative to workingDirectory
    let fullPath: String
    let isDirectory: Bool
    let fileSize: Int
}

struct ChatComposerView: View {
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    @Binding var agentEnabled: Bool
    @Binding var dangerousMode: Bool
    @Binding var workingDirectory: String?
    let undoCount: Int
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onShowUndo: () -> Void

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var isShowingDirectoryPicker = false

    // @-mention state
    @State private var showMentionPopup = false
    @State private var mentionQuery = ""           // text after the last '@'
    @State private var mentionResults: [MentionEntry] = []
    @State private var mentionSelectedIndex = 0
    @State private var previousDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            // Attachment chips
            if !attachments.isEmpty {
                attachmentChips
            }

            // Input row
            VStack(spacing: 0) {
                // @-mention popup (floats above the text input)
                if showMentionPopup && !mentionResults.isEmpty {
                    mentionPopupView
                }

                // Text input
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 20, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($isFocused)
                        .onChange(of: draft) { _, newValue in
                            handleDraftChange(newValue)
                        }

                    if draft.isEmpty && attachments.isEmpty {
                        Text("Message (\u{21B5} to send) \u{2022} @ to mention files")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textTertiary)
                            .allowsHitTesting(false)
                            .padding(.top, 0)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Bottom bar: attach + @ mention + agent toggle + stop
                HStack(spacing: 8) {
                    Button {
                        presentAttachmentOpenPanel()
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach file (images, text, code)")

                    // @ mention button
                    Button {
                        if workingDirectory != nil {
                            // Insert @ at end of draft and trigger popup
                            draft += "@"
                        }
                    } label: {
                        Text("@")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(workingDirectory != nil ? theme.textSecondary : theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(workingDirectory == nil)
                    .help(workingDirectory != nil
                        ? "Mention a file from working directory"
                        : "Set a working directory first to mention files")

                    // Agent mode toggle
                    Button {
                        if agentEnabled {
                            agentEnabled = false
                        } else {
                            if workingDirectory == nil {
                                isShowingDirectoryPicker = true
                            } else {
                                agentEnabled = true
                            }
                        }
                    } label: {
                        Image(systemName: "terminal")
                            .font(.system(size: 14))
                            .foregroundStyle(agentEnabled ? theme.accent : theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(agentEnabled
                        ? "Agent mode ON — click to disable"
                        : "Enable agent mode (or type /agent <path>)")

                    // Dangerous mode toggle (only shown when agent is enabled)
                    if agentEnabled {
                        Button {
                            dangerousMode.toggle()
                        } label: {
                            Image(systemName: dangerousMode ? "bolt.fill" : "bolt")
                                .font(.system(size: 13))
                                .foregroundStyle(dangerousMode ? Color.red : theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(dangerousMode
                            ? "Dangerous mode ON — auto-approves all tools. Click to disable"
                            : "Enable dangerous mode — auto-approve tools (changes can be reverted)")
                    }

                    // Undo history button (shown when there are tracked changes)
                    if undoCount > 0 {
                        Button {
                            onShowUndo()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11))
                                Text("\(undoCount)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.1), in: Capsule())
                            .overlay(Capsule().stroke(.orange.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("View change history (\(undoCount) revertable)")
                    }

                    // Working directory chip (shown when agent mode is on)
                    if agentEnabled, let dir = workingDirectory {
                        Button {
                            isShowingDirectoryPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                Text(abbreviatePath(dir))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Working directory — click to change")
                    }

                    Spacer()

                    if isSending {
                        Button {
                            onStop()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .help("Stop generation (Esc)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.composerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isFocused ? theme.composerBorderFocused : theme.composerBorder, lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .onKeyPress(.return, phases: .down) { keyPress in
            if showMentionPopup && !mentionResults.isEmpty {
                selectMention(mentionResults[mentionSelectedIndex])
                return .handled
            }
            if keyPress.modifiers.isEmpty && canSend {
                onSend()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            if showMentionPopup && !mentionResults.isEmpty {
                mentionSelectedIndex = max(0, mentionSelectedIndex - 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            if showMentionPopup && !mentionResults.isEmpty {
                mentionSelectedIndex = min(mentionResults.count - 1, mentionSelectedIndex + 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape, phases: .down) { _ in
            if showMentionPopup {
                dismissMentionPopup()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.tab, phases: .down) { _ in
            if showMentionPopup && !mentionResults.isEmpty {
                let entry = mentionResults[mentionSelectedIndex]
                if entry.isDirectory {
                    // Navigate into directory
                    navigateIntoDirectory(entry)
                    return .handled
                } else {
                    selectMention(entry)
                    return .handled
                }
            }
            return .ignored
        }
        .fileImporter(
            isPresented: $isShowingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectoryPick(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - @-mention popup view

    private var mentionPopupView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                Text(mentionSubdirectoryLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(mentionResults.count) items")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()
                .foregroundStyle(theme.chipBorder)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(mentionResults.enumerated()), id: \.element.id) { index, entry in
                            mentionRow(entry, isSelected: index == mentionSelectedIndex)
                                .id(entry.id)
                                .onTapGesture {
                                    if entry.isDirectory {
                                        navigateIntoDirectory(entry)
                                    } else {
                                        selectMention(entry)
                                    }
                                }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .onChange(of: mentionSelectedIndex) { _, newIndex in
                    if newIndex < mentionResults.count {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(mentionResults[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.composerBackground)
                .shadow(color: .black.opacity(0.2), radius: 8, y: -2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.composerBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func mentionRow(_ entry: MentionEntry, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry.name))
                .font(.system(size: 12))
                .foregroundStyle(entry.isDirectory ? Color.blue : theme.textSecondary)
                .frame(width: 16)

            Text(entry.name)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            Spacer()

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary)
            } else {
                Text(fileSizeLabel(entry.fileSize))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? theme.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private var mentionSubdirectoryLabel: String {
        // Extract subdirectory part from mentionQuery
        let query = mentionQuery
        if let lastSlash = query.lastIndex(of: "/") {
            let subdir = String(query[query.startIndex...lastSlash])
            return "./\(subdir)"
        }
        return "./"
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json", "yml", "yaml", "toml": return "doc.text"
        case "md": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "sh", "bash", "zsh": return "terminal"
        default: return "doc"
        }
    }

    private func fileSizeLabel(_ size: Int) -> String {
        if size < 1024 { return "\(size) B" }
        else if size < 1024 * 1024 { return "\(size / 1024) KB" }
        else { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
    }

    // MARK: - @-mention logic

    /// Called whenever the draft text changes. Detects '@' and extracts query.
    private func handleDraftChange(_ newValue: String) {
        previousDraft = newValue

        guard workingDirectory != nil else {
            if showMentionPopup { dismissMentionPopup() }
            return
        }

        // Find the last '@' in the draft that isn't preceded by a word character (or is at start)
        guard let atIndex = findActiveMentionAtIndex(in: newValue) else {
            if showMentionPopup { dismissMentionPopup() }
            return
        }

        // Extract query text after '@'
        let queryStart = newValue.index(after: atIndex)
        let query = String(newValue[queryStart...])

        // If query contains a space, the mention is complete — dismiss
        if query.contains(" ") || query.contains("\n") {
            if showMentionPopup { dismissMentionPopup() }
            return
        }

        mentionQuery = query
        mentionSelectedIndex = 0
        updateMentionResults()
        showMentionPopup = true
    }

    /// Finds the index of the '@' character that initiated the current mention.
    /// Returns nil if no active mention context is found.
    private func findActiveMentionAtIndex(in text: String) -> String.Index? {
        // Walk backwards from end to find the last '@'
        guard let atRange = text.range(of: "@", options: .backwards) else { return nil }
        let atIndex = atRange.lowerBound

        // Check that there's no space or newline between '@' and end of text
        let afterAt = text[text.index(after: atIndex)...]
        if afterAt.contains(" ") || afterAt.contains("\n") {
            return nil
        }

        // '@' should be at start of text or preceded by a space/newline
        if atIndex == text.startIndex { return atIndex }
        let charBefore = text[text.index(before: atIndex)]
        if charBefore == " " || charBefore == "\n" || charBefore == "\t" {
            return atIndex
        }

        return nil
    }

    /// Lists files from the working directory, filtered by mentionQuery.
    private func updateMentionResults() {
        guard let workDir = workingDirectory else {
            mentionResults = []
            return
        }

        let fm = FileManager.default

        // Determine base directory and filter text
        var basePath = workDir
        var filterText = mentionQuery

        // Support subdirectory traversal: if query contains '/', split into path + filter
        if let lastSlash = mentionQuery.lastIndex(of: "/") {
            let subdir = String(mentionQuery[mentionQuery.startIndex..<lastSlash])
            filterText = String(mentionQuery[mentionQuery.index(after: lastSlash)...])

            // Resolve subdirectory relative to workDir
            let resolvedSub = (workDir as NSString).appendingPathComponent(subdir)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: resolvedSub, isDirectory: &isDir), isDir.boolValue {
                basePath = resolvedSub
            } else {
                mentionResults = []
                return
            }
        }

        // List directory contents
        guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else {
            mentionResults = []
            return
        }

        // Hidden files/directories and common noise to skip
        let skipDirs: Set<String> = [".git", ".build", "node_modules", ".DS_Store", "__pycache__", ".swiftpm", "DerivedData"]

        var entries: [MentionEntry] = []
        for name in contents {
            // Skip hidden files unless query starts with '.'
            if name.hasPrefix(".") && !filterText.hasPrefix(".") { continue }
            if skipDirs.contains(name) { continue }

            // Filter by typed text (case-insensitive prefix/contains match)
            if !filterText.isEmpty {
                let nameLower = name.lowercased()
                let filterLower = filterText.lowercased()
                if !nameLower.contains(filterLower) { continue }
            }

            let fullPath = (basePath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            let relativePath: String
            if let lastSlash = mentionQuery.lastIndex(of: "/") {
                let subdir = String(mentionQuery[mentionQuery.startIndex...lastSlash])
                relativePath = subdir + name
            } else {
                relativePath = name
            }

            var fileSize = 0
            if !isDir.boolValue {
                fileSize = (try? fm.attributesOfItem(atPath: fullPath)[.size] as? Int) ?? 0
            }

            entries.append(MentionEntry(
                name: name,
                relativePath: relativePath,
                fullPath: fullPath,
                isDirectory: isDir.boolValue,
                fileSize: fileSize
            ))
        }

        // Sort: directories first, then alphabetical
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        // Cap results
        mentionResults = Array(entries.prefix(50))
    }

    /// Selects a file mention: replaces @query in draft with @filename and attaches the file.
    private func selectMention(_ entry: MentionEntry) {
        guard !entry.isDirectory else {
            navigateIntoDirectory(entry)
            return
        }

        // Replace the @query portion in the draft with @relativePath
        if let atIndex = findActiveMentionAtIndex(in: draft) {
            let before = String(draft[draft.startIndex..<atIndex])
            draft = before + "@\(entry.relativePath) "
        }

        // Attach the file
        let url = URL(fileURLWithPath: entry.fullPath)
        if let attachment = loadAttachment(from: url) {
            attachments.append(attachment)
        }

        dismissMentionPopup()
    }

    /// Navigate into a directory in the mention popup.
    private func navigateIntoDirectory(_ entry: MentionEntry) {
        // Update the draft's @query to include the directory path
        if let atIndex = findActiveMentionAtIndex(in: draft) {
            let before = String(draft[draft.startIndex..<atIndex])
            draft = before + "@\(entry.relativePath)/"
            // handleDraftChange will be called by onChange and update the popup
        }
    }

    private func dismissMentionPopup() {
        showMentionPopup = false
        mentionQuery = ""
        mentionResults = []
        mentionSelectedIndex = 0
    }

    // MARK: - Attachment chips

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private func attachmentChip(_ attachment: Attachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.isImage ? "photo" : (attachment.isText ? "doc.text" : "doc"))
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)

            Text(attachment.fileName)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            Text(attachment.fileSizeLabel)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.chipBackground, in: Capsule())
        .overlay(Capsule().stroke(theme.chipBorder, lineWidth: 1))
    }

    // MARK: - File handling

    private func appendAttachments(from urls: [URL]) {
        for url in urls {
            if let attachment = loadAttachment(from: url) {
                attachments.append(attachment)
            }
        }
    }

    private func presentAttachmentOpenPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.item]
        panel.title = "Attach Files"
        panel.prompt = "Attach"

        if panel.runModal() == .OK {
            appendAttachments(from: panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else { return }
                if let attachment = loadAttachment(from: url) {
                    DispatchQueue.main.async {
                        attachments.append(attachment)
                    }
                }
            }
        }
    }

    private func handleDirectoryPick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let path = url.path
        workingDirectory = path
        agentEnabled = true
    }

    /// Abbreviate a path for display (e.g. /Users/name/Projects/foo -> ~/Projects/foo)
    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        // Show only last 2 path components if long
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

/// Load a file from disk into an Attachment.
/// Images are base64-encoded; text files are read as UTF-8 strings.
func loadAttachment(from url: URL) -> Attachment? {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    guard let data = try? Data(contentsOf: url) else { return nil }

    let fileName = url.lastPathComponent
    let mimeType = guessMimeType(for: url)
    let fileSize = data.count

    // For images, base64 encode
    if mimeType.hasPrefix("image/") {
        let base64 = data.base64EncodedString()
        return Attachment(id: UUID(), fileName: fileName, mimeType: mimeType, content: base64, fileSize: fileSize)
    }

    // For text-like files, read as string
    let textMime = mimeType.hasPrefix("text/") ||
        mimeType == "application/json" ||
        mimeType == "application/xml" ||
        mimeType == "application/javascript"
    let textExt = [
        "md", "swift", "py", "rs", "ts", "tsx", "jsx", "js", "css", "html",
        "yml", "yaml", "toml", "sh", "bash", "c", "cpp", "h", "go", "rb",
        "java", "kt", "sql", "env", "csv", "log"
    ].contains(url.pathExtension.lowercased())

    if textMime || textExt {
        let text = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        return Attachment(id: UUID(), fileName: fileName, mimeType: mimeType, content: text, fileSize: fileSize)
    }

    // Other files: store base64
    let base64 = data.base64EncodedString()
    return Attachment(id: UUID(), fileName: fileName, mimeType: mimeType, content: base64, fileSize: fileSize)
}

private func guessMimeType(for url: URL) -> String {
    if let utType = UTType(filenameExtension: url.pathExtension),
       let mime = utType.preferredMIMEType {
        return mime
    }
    // Fallback guesses
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "md": return "text/markdown"
    case "swift": return "text/x-swift"
    case "py": return "text/x-python"
    case "ts", "tsx": return "text/typescript"
    case "jsx": return "text/javascript"
    case "yml", "yaml": return "text/yaml"
    case "toml": return "text/toml"
    case "rs": return "text/x-rust"
    case "go": return "text/x-go"
    case "kt": return "text/x-kotlin"
    default: return "application/octet-stream"
    }
}
