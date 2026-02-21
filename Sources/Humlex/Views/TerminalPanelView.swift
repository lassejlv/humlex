import SwiftUI

/// Native terminal panel with full PTY support
struct TerminalPanelView: View {
    @Binding var isExpanded: Bool
    let workingDirectory: String?

    @Environment(\.appTheme) private var theme
    @StateObject private var pty = PseudoTerminal()
    @State private var panelHeight: CGFloat = 250
    @State private var inputBuffer: String = ""
    @FocusState private var isInputFocused: Bool

    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 500
    private let collapsedHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader

            if isExpanded {
                theme.divider.frame(height: 1)
                terminalContent
            }
        }
        .frame(height: isExpanded ? panelHeight : collapsedHeight)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        .overlay(alignment: .top) {
            theme.divider.frame(height: 1)
        }
        .onAppear {
            startTerminalIfNeeded()
        }
        .onDisappear {
            pty.stop()
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                startTerminalIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
    }

    private var terminalHeader: some View {
        HStack(spacing: 10) {
            // Drag handle for resizing
            if isExpanded {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.textTertiary.opacity(0.5))
                    .frame(width: 36, height: 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newHeight = panelHeight - value.translation.height
                                panelHeight = min(maxHeight, max(minHeight, newHeight))
                            }
                    )
                    .padding(.vertical, 4)
            }

            // Terminal icon and title
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                Text("Terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                // Shell indicator
                let shellName = (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
                    .components(separatedBy: "/").last ?? "shell"
                Text(shellName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)

                // Running indicator
                if pty.isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            // Clear button
            if isExpanded {
                Button {
                    pty.clearOutput()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear terminal")

                // Kill button (Ctrl+C)
                Button {
                    pty.sendInterrupt()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Send interrupt (Ctrl+C)")
            }

            // Close button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Close terminal" : "Open terminal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isExpanded ? 6 : 0)
        .frame(height: collapsedHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            // Terminal output with ANSI rendering
            TerminalOutputView(text: pty.outputText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input area
            HStack(spacing: 0) {
                TerminalInputField(
                    text: $inputBuffer,
                    isFocused: $isInputFocused,
                    onSubmit: {
                        pty.sendLine(inputBuffer)
                        inputBuffer = ""
                    },
                    onInterrupt: {
                        pty.sendInterrupt()
                    },
                    onEOF: {
                        pty.sendEOF()
                    },
                    onTab: {
                        pty.send("\t")
                    }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        }
    }

    private func startTerminalIfNeeded() {
        if !pty.isRunning {
            // Update working directory if provided
            if let dir = workingDirectory {
                // We'll cd to it after shell starts
                pty.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pty.sendLine("cd \"\(dir)\" && clear")
                }
            } else {
                pty.start()
            }
        }
    }
}

// MARK: - Terminal Output View

struct TerminalOutputView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(attributedOutput)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .id("bottom")
            }
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.05)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    private var attributedOutput: AttributedString {
        // Parse ANSI escape codes and convert to AttributedString
        ANSIParser.parse(text)
    }
}

// MARK: - Terminal Input Field

struct TerminalInputField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onInterrupt: () -> Void
    let onEOF: () -> Void
    let onTab: () -> Void

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.white)
            .focused(isFocused)
            .onSubmit(onSubmit)
            .onKeyPress(.tab) {
                onTab()
                return .handled
            }
    }
}

// MARK: - ANSI Parser

enum ANSIParser {
    static func parse(_ text: String) -> AttributedString {
        var result = AttributedString()
        var currentAttributes = AttributeContainer()
        currentAttributes.foregroundColor = .white

        // Regex to match ANSI escape sequences
        let pattern = "\u{001B}\\[([0-9;]*)m"
        let regex = try? NSRegularExpression(pattern: pattern)

        var lastEnd = text.startIndex
        let nsText = text as NSString

        regex?.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match = match else { return }

            // Add text before this escape sequence
            if let range = Range(match.range, in: text) {
                let beforeRange = lastEnd..<range.lowerBound
                if !beforeRange.isEmpty {
                    var segment = AttributedString(text[beforeRange])
                    segment.mergeAttributes(currentAttributes)
                    result += segment
                }
                lastEnd = range.upperBound

                // Parse the escape sequence
                if let codeRange = Range(match.range(at: 1), in: text) {
                    let codes = text[codeRange].split(separator: ";").compactMap { Int($0) }
                    currentAttributes = applyANSICodes(codes, to: currentAttributes)
                }
            }
        }

        // Add remaining text
        if lastEnd < text.endIndex {
            var segment = AttributedString(text[lastEnd...])
            segment.mergeAttributes(currentAttributes)
            result += segment
        }

        return result
    }

    private static func applyANSICodes(_ codes: [Int], to attributes: AttributeContainer) -> AttributeContainer {
        var attrs = attributes

        for code in codes {
            switch code {
            case 0: // Reset
                attrs = AttributeContainer()
                attrs.foregroundColor = .white
            case 1: // Bold
                attrs.font = .system(size: 12, weight: .bold, design: .monospaced)
            case 2: // Dim
                attrs.foregroundColor = attrs.foregroundColor?.opacity(0.6)
            case 3: // Italic
                attrs.font = .system(size: 12, design: .monospaced).italic()
            case 4: // Underline
                attrs.underlineStyle = .single
            case 30: attrs.foregroundColor = .black
            case 31: attrs.foregroundColor = Color(red: 1.0, green: 0.33, blue: 0.33) // Red
            case 32: attrs.foregroundColor = Color(red: 0.33, green: 0.86, blue: 0.33) // Green
            case 33: attrs.foregroundColor = Color(red: 1.0, green: 0.86, blue: 0.33) // Yellow
            case 34: attrs.foregroundColor = Color(red: 0.33, green: 0.53, blue: 1.0) // Blue
            case 35: attrs.foregroundColor = Color(red: 0.86, green: 0.33, blue: 0.86) // Magenta
            case 36: attrs.foregroundColor = Color(red: 0.33, green: 0.86, blue: 0.86) // Cyan
            case 37: attrs.foregroundColor = .white
            case 90: attrs.foregroundColor = .gray // Bright black
            case 91: attrs.foregroundColor = Color(red: 1.0, green: 0.5, blue: 0.5) // Bright red
            case 92: attrs.foregroundColor = Color(red: 0.5, green: 1.0, blue: 0.5) // Bright green
            case 93: attrs.foregroundColor = Color(red: 1.0, green: 1.0, blue: 0.5) // Bright yellow
            case 94: attrs.foregroundColor = Color(red: 0.5, green: 0.7, blue: 1.0) // Bright blue
            case 95: attrs.foregroundColor = Color(red: 1.0, green: 0.5, blue: 1.0) // Bright magenta
            case 96: attrs.foregroundColor = Color(red: 0.5, green: 1.0, blue: 1.0) // Bright cyan
            case 97: attrs.foregroundColor = .white // Bright white
            default: break
            }
        }

        return attrs
    }
}
