import AppKit
import SwiftUI

/// Produces a syntax-highlighted `AttributedString` for a code snippet.
/// Uses a simple keyword/token-based highlighter that covers the most common
/// patterns across popular languages. Accepts an `AppTheme` to determine colors.
enum SyntaxHighlighter {

    // MARK: - Public

    static func highlight(_ code: String, language: String?, theme: AppTheme = .system) -> AttributedString {
        let lang = (language ?? "").lowercased()
        let tokens = tokenize(code, language: lang)
        return buildAttributedString(from: tokens, theme: theme)
    }

    // MARK: - Token types

    private enum TokenKind {
        case plain
        case keyword
        case string
        case comment
        case number
        case type
        case function
        case punctuation
    }

    private struct Token {
        let text: String
        let kind: TokenKind
    }

    // MARK: - Colors (theme-aware)

    private static func color(for kind: TokenKind, theme: AppTheme) -> Color {
        switch kind {
        case .plain:       return theme.syntaxPlain
        case .keyword:     return theme.syntaxKeyword
        case .string:      return theme.syntaxString
        case .comment:     return theme.syntaxComment
        case .number:      return theme.syntaxNumber
        case .type:        return theme.syntaxType
        case .function:    return theme.syntaxFunction
        case .punctuation: return theme.syntaxPunctuation
        }
    }

    // MARK: - Keyword sets

    private static let swiftKeywords: Set<String> = [
        "import", "func", "var", "let", "if", "else", "guard", "return", "struct", "class",
        "enum", "protocol", "extension", "case", "switch", "for", "while", "in", "where",
        "throws", "throw", "try", "catch", "async", "await", "do", "self", "Self",
        "true", "false", "nil", "static", "private", "public", "internal", "fileprivate",
        "open", "override", "init", "deinit", "typealias", "associatedtype", "some", "any",
        "weak", "unowned", "lazy", "mutating", "nonmutating", "defer", "break", "continue",
        "fallthrough", "repeat", "default", "is", "as", "super", "convenience", "required",
        "final", "inout", "operator", "subscript", "willSet", "didSet", "get", "set",
        "@State", "@Binding", "@Published", "@ObservedObject", "@StateObject", "@Environment",
        "@MainActor", "@Sendable", "@escaping", "@ViewBuilder", "@main", "@available",
        "@discardableResult", "@objc"
    ]

    private static let jsKeywords: Set<String> = [
        "const", "let", "var", "function", "return", "if", "else", "for", "while", "do",
        "switch", "case", "break", "continue", "class", "extends", "new", "this", "super",
        "import", "export", "default", "from", "async", "await", "try", "catch", "throw",
        "typeof", "instanceof", "in", "of", "true", "false", "null", "undefined", "void",
        "yield", "static", "get", "set", "constructor", "interface", "type", "enum",
        "implements", "public", "private", "protected", "readonly", "abstract", "as",
        "declare", "module", "namespace", "require"
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import", "from",
        "as", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass",
        "break", "continue", "and", "or", "not", "in", "is", "True", "False", "None",
        "global", "nonlocal", "del", "assert", "async", "await", "self", "print"
    ]

    private static let genericKeywords: Set<String> = [
        "if", "else", "for", "while", "return", "func", "function", "var", "let", "const",
        "class", "struct", "enum", "import", "export", "true", "false", "null", "nil",
        "new", "this", "self", "try", "catch", "throw", "switch", "case", "break",
        "continue", "default", "do", "in", "of", "async", "await", "yield", "static",
        "public", "private", "protected", "void", "int", "float", "double", "string",
        "bool", "boolean", "char", "byte", "long", "short", "unsigned", "signed",
        "package", "interface", "implements", "extends", "override", "final", "abstract",
        "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP",
        "ALTER", "TABLE", "INTO", "VALUES", "SET", "JOIN", "ON", "AND", "OR", "NOT",
        "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "AS", "NULL", "DISTINCT",
        "INNER", "LEFT", "RIGHT", "OUTER", "INDEX", "PRIMARY", "KEY", "FOREIGN",
        "REFERENCES", "CASCADE", "CONSTRAINT", "CHECK", "UNIQUE", "DEFAULT", "EXISTS",
        "UNION", "ALL", "COUNT", "SUM", "AVG", "MAX", "MIN", "BETWEEN", "LIKE", "IN",
        "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT", "ROLLBACK"
    ]

    private static let swiftTypes: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "URL", "Data", "Date", "UUID", "View", "Text",
        "Button", "VStack", "HStack", "ZStack", "List", "ForEach", "Image",
        "NavigationStack", "NavigationSplitView", "Color", "Font"
    ]

    private static func keywords(for lang: String) -> Set<String> {
        switch lang {
        case "swift": return swiftKeywords
        case "javascript", "js", "typescript", "ts", "tsx", "jsx": return jsKeywords
        case "python", "py": return pythonKeywords
        default: return genericKeywords
        }
    }

    // MARK: - Tokenizer

    private static func tokenize(_ code: String, language: String) -> [Token] {
        let kw = keywords(for: language)
        var tokens: [Token] = []
        let chars = Array(code)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Line comment
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                let start = i
                while i < chars.count && chars[i] != "\n" { i += 1 }
                tokens.append(Token(text: String(chars[start..<i]), kind: .comment))
                continue
            }
            // Python/shell comment
            if c == "#" && (language == "python" || language == "py" || language == "bash" || language == "sh" || language == "shell" || language == "yaml" || language == "yml" || language == "ruby" || language == "rb") {
                let start = i
                while i < chars.count && chars[i] != "\n" { i += 1 }
                tokens.append(Token(text: String(chars[start..<i]), kind: .comment))
                continue
            }
            // SQL comment
            if c == "-" && i + 1 < chars.count && chars[i + 1] == "-" && (language == "sql") {
                let start = i
                while i < chars.count && chars[i] != "\n" { i += 1 }
                tokens.append(Token(text: String(chars[start..<i]), kind: .comment))
                continue
            }
            // Block comment
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                if i + 1 < chars.count { i += 2 } else { i = chars.count }
                tokens.append(Token(text: String(chars[start..<i]), kind: .comment))
                continue
            }

            // Strings
            if c == "\"" || c == "'" || c == "`" {
                let quote = c
                let start = i
                i += 1
                while i < chars.count && chars[i] != quote {
                    if chars[i] == "\\" { i += 1 } // skip escaped
                    i += 1
                }
                if i < chars.count { i += 1 }
                tokens.append(Token(text: String(chars[start..<i]), kind: .string))
                continue
            }

            // Numbers
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                let start = i
                while i < chars.count && (chars[i].isNumber || chars[i] == "." || chars[i] == "x" || chars[i] == "X" ||
                        (chars[i] >= "a" && chars[i] <= "f") || (chars[i] >= "A" && chars[i] <= "F") || chars[i] == "_") {
                    i += 1
                }
                tokens.append(Token(text: String(chars[start..<i]), kind: .number))
                continue
            }

            // Identifiers / keywords
            if c.isLetter || c == "_" || c == "@" {
                let start = i
                i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
                let word = String(chars[start..<i])

                if kw.contains(word) {
                    tokens.append(Token(text: word, kind: .keyword))
                } else if language == "swift" && swiftTypes.contains(word) {
                    tokens.append(Token(text: word, kind: .type))
                } else if word.first?.isUppercase == true {
                    tokens.append(Token(text: word, kind: .type))
                } else if i < chars.count && chars[i] == "(" {
                    tokens.append(Token(text: word, kind: .function))
                } else {
                    tokens.append(Token(text: word, kind: .plain))
                }
                continue
            }

            // Punctuation / operators
            if "{}[]().,;:+-*/%=<>&|!?^~@".contains(c) {
                tokens.append(Token(text: String(c), kind: .punctuation))
                i += 1
                continue
            }

            // Whitespace and other
            let start = i
            i += 1
            tokens.append(Token(text: String(chars[start..<i]), kind: .plain))
        }

        return tokens
    }

    // MARK: - Build AttributedString

    private static func buildAttributedString(from tokens: [Token], theme: AppTheme) -> AttributedString {
        var result = AttributedString()
        for token in tokens {
            var part = AttributedString(token.text)
            part.foregroundColor = color(for: token.kind, theme: theme)
            part.font = .system(.callout, design: .monospaced)
            result.append(part)
        }
        return result
    }
}
