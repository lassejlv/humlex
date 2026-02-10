import SwiftUI
import UniformTypeIdentifiers

struct ChatComposerView: View {
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var isShowingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Attachment chips
            if !attachments.isEmpty {
                attachmentChips
            }

            // Input row
            VStack(spacing: 0) {
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

                    if draft.isEmpty && attachments.isEmpty {
                        Text("Enter a message here, press \u{21B5} to send")
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

                // Bottom bar: attach + stop
                HStack(spacing: 8) {
                    Button {
                        isShowingFilePicker = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach file")

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
                        .help("Stop (Esc)")
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
            if keyPress.modifiers.isEmpty && canSend {
                onSend()
                return .handled
            }
            return .ignored
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFilePick(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
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

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            if let attachment = loadAttachment(from: url) {
                attachments.append(attachment)
            }
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
