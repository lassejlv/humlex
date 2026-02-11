import AppKit
import SwiftUI

/// A SwiftUI view that renders Markdown text into native views with proper
/// headings, paragraphs, syntax-highlighted code blocks, lists, inline
/// formatting, and links. Works during streaming too.
struct MarkdownView: View {
    let source: String
    let isStreaming: Bool

    @Environment(\.appTheme) private var theme

    init(source: String, isStreaming: Bool = false) {
        self.source = source
        self.isStreaming = isStreaming
    }

    var body: some View {
        let blocks = parseBlocks(source)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                renderBlock(block, isLast: idx == blocks.count - 1)
            }
        }
    }

    // MARK: - Block types

    private enum Block {
        case heading(level: Int, text: String)
        case codeBlock(language: String?, code: String, closed: Bool)
        case table(headers: [String], rows: [[String]])
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case paragraph(text: String)
        case horizontalRule
    }

    // MARK: - Parsing

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language = lang.isEmpty ? nil : lang
                var codeLines: [String] = []
                i += 1
                var closed = false
                while i < lines.count {
                    if lines[i].hasPrefix("```") {
                        closed = true
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n"), closed: closed))
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 && trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) {
                let chars = Set(trimmed)
                if chars.count == 1 {
                    blocks.append(.horizontalRule)
                    i += 1
                    continue
                }
            }

            // Heading
            if let headingMatch = parseHeading(line) {
                blocks.append(.heading(level: headingMatch.0, text: headingMatch.1))
                i += 1
                continue
            }

            // Markdown table
            if let table = parseTable(lines: lines, index: i) {
                blocks.append(.table(headers: table.headers, rows: table.rows))
                i = table.nextIndex
                continue
            }

            // Unordered list
            if isUnorderedListItem(line) {
                var items: [String] = []
                while i < lines.count && isUnorderedListItem(lines[i]) {
                    items.append(stripListPrefix(lines[i]))
                    i += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOrderedListItem(line) {
                var items: [String] = []
                while i < lines.count && isOrderedListItem(lines[i]) {
                    items.append(stripOrderedListPrefix(lines[i]))
                    i += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty || l.hasPrefix("```") || parseHeading(l) != nil
                    || isUnorderedListItem(l) || isOrderedListItem(l)
                    || parseTable(lines: lines, index: i) != nil {
                    break
                }
                paraLines.append(l)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    private func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        guard line.count > level && line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        return (level, String(line.dropFirst(level + 1)))
    }

    private func isUnorderedListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private func stripListPrefix(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
            return String(t.dropFirst(2))
        }
        return t
    }

    private func isOrderedListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        guard let dotIdx = t.firstIndex(of: ".") else { return false }
        let prefix = t[t.startIndex..<dotIdx]
        guard prefix.allSatisfy(\.isNumber), !prefix.isEmpty else { return false }
        let afterDot = t.index(after: dotIdx)
        return afterDot < t.endIndex && t[afterDot] == " "
    }

    private func stripOrderedListPrefix(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        guard let dotIdx = t.firstIndex(of: ".") else { return t }
        let afterDot = t.index(after: dotIdx)
        guard afterDot < t.endIndex, t[afterDot] == " " else { return t }
        return String(t[t.index(afterDot, offsetBy: 1)...])
    }

    private func parseTable(lines: [String], index: Int) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }

        let headerLine = lines[index]
        let separatorLine = lines[index + 1]

        guard isTableRowLine(headerLine), isTableSeparatorLine(separatorLine) else {
            return nil
        }

        let headers = parseTableCells(headerLine)
        guard headers.count >= 2 else { return nil }

        var rows: [[String]] = []
        var i = index + 2
        while i < lines.count {
            let rowLine = lines[i]
            if rowLine.trimmingCharacters(in: .whitespaces).isEmpty || !isTableRowLine(rowLine) {
                break
            }

            var cells = parseTableCells(rowLine)
            if cells.count < headers.count {
                cells += Array(repeating: "", count: headers.count - cells.count)
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            i += 1
        }

        return (headers: headers, rows: rows, nextIndex: i)
    }

    private func isTableRowLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let cells = parseTableCells(trimmed)
        return cells.count >= 2
    }

    private func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }

        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard parts.count >= 2 else { return false }

        return parts.allSatisfy { part in
            guard part.allSatisfy({ $0 == "-" || $0 == ":" }) else { return false }
            let dashCount = part.filter { $0 == "-" }.count
            return dashCount >= 3
        }
    }

    private func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        var cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        // Some model outputs include an extra trailing pipe (e.g. "||") which
        // becomes a phantom empty column. Trim only outer empty cells so we keep
        // intentional empty cells inside the table.
        while cells.first == "" {
            cells.removeFirst()
        }
        while cells.last == "" {
            cells.removeLast()
        }

        return cells
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: Block, isLast: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)

        case .codeBlock(let language, let code, let closed):
            CodeBlockView(language: language, code: code, closed: closed, showCursor: isStreaming && isLast && !closed)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(theme.textSecondary)
                        inlineMarkdown(item)
                    }
                }
            }
            .padding(.leading, 4)

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(theme.textSecondary)
                            .monospacedDigit()
                        inlineMarkdown(item)
                    }
                }
            }
            .padding(.leading, 4)

        case .paragraph(let text):
            let displayText = isStreaming && isLast ? text + " \u{258D}" : text
            inlineMarkdown(displayText)

        case .horizontalRule:
            theme.divider.frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                        tableCell(cell, isHeader: true)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            tableCell(cell, isHeader: false)
                        }
                    }
                }
            }
        }
        .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.codeBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        inlineMarkdown(text.isEmpty ? " " : text)
            .font(isHeader ? .system(size: 13, weight: .semibold) : .system(size: 13))
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHeader ? theme.codeHeaderBackground.opacity(0.6) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(theme.codeBorder.opacity(0.55))
                    .frame(width: 1),
                alignment: .trailing
            )
            .overlay(
                Rectangle()
                    .fill(theme.codeBorder.opacity(0.55))
                    .frame(height: 1),
                alignment: .bottom
            )
    }

    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
        inlineMarkdown(text)
            .font(font)
            .padding(.top, level <= 2 ? 4 : 2)
    }

    // MARK: - Inline markdown

    @ViewBuilder
    private func inlineMarkdown(_ source: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .foregroundStyle(theme.textPrimary)
                .tint(theme.accent)
        } else {
            Text(source)
                .foregroundStyle(theme.textPrimary)
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String?
    let code: String
    let closed: Bool
    let showCursor: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.toastManager) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language + copy (not text-selectable)
            header

            theme.divider.frame(height: 1)
                .opacity(0.5)

            // Code content (text-selectable)
            ScrollView(.horizontal, showsIndicators: false) {
                codeContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .textSelection(.enabled)
            }
        }
        .textSelection(.disabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.codeBorder, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(language ?? "code")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .textSelection(.disabled)

            Spacer()

            copyButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.codeHeaderBackground)
        .textSelection(.disabled)
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            toast.show(.success("Copied to clipboard"))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                Text("Copy")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var codeContent: some View {
        let highlighted = SyntaxHighlighter.highlight(code, language: language, theme: theme)
        let display: AttributedString
        if showCursor {
            var cursor = AttributedString(" \u{258D}")
            cursor.foregroundColor = .secondary
            cursor.font = .system(.callout, design: .monospaced)
            display = highlighted + cursor
        } else {
            display = highlighted
        }
        return Text(display)
            .textSelection(.enabled)
    }
}
