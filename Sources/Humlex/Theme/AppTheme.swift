import SwiftUI

// MARK: - Theme Definition

struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String

    /// Whether this theme overrides the window chrome or uses system default.
    let isCustom: Bool

    // --- App chrome ---
    let background: Color           // main chat area background
    let sidebarBackground: Color    // sidebar background
    let surfaceBackground: Color    // cards, composer, popovers
    let divider: Color              // dividers & separators

    // --- Text ---
    let textPrimary: Color          // main body text
    let textSecondary: Color        // timestamps, labels, hints
    let textTertiary: Color         // placeholder, very muted

    // --- Selection / Interactive ---
    let accent: Color               // accent / tint color
    let selectionBackground: Color  // selected list row, button highlight
    let hoverBackground: Color      // hover state on rows

    // --- Chat ---
    let userBubble: Color           // user message bubble fill
    let userBubbleText: Color       // user message text
    let assistantBackground: Color  // assistant message area (usually clear)

    // --- Composer ---
    let composerBackground: Color   // input field background
    let composerBorder: Color       // input field border
    let composerBorderFocused: Color // input field border when focused

    // --- Code block ---
    let codeBackground: Color
    let codeBorder: Color
    let codeHeaderBackground: Color

    // --- Syntax highlighting ---
    let syntaxKeyword: Color
    let syntaxString: Color
    let syntaxComment: Color
    let syntaxNumber: Color
    let syntaxType: Color
    let syntaxFunction: Color
    let syntaxPunctuation: Color
    let syntaxPlain: Color

    // --- Attachment chips ---
    let chipBackground: Color
    let chipBorder: Color
}

// MARK: - Built-in Themes

extension AppTheme {

    /// System default — uses semantic NSColor values, adapts to macOS light/dark.
    static let system = AppTheme(
        id: "system",
        name: "System",
        isCustom: false,

        background: Color(nsColor: .windowBackgroundColor),
        sidebarBackground: Color.clear,
        surfaceBackground: Color(nsColor: .controlBackgroundColor),
        divider: Color(nsColor: .separatorColor),

        textPrimary: Color(nsColor: .textColor),
        textSecondary: Color(nsColor: .secondaryLabelColor),
        textTertiary: Color(nsColor: .tertiaryLabelColor),

        accent: Color.accentColor,
        selectionBackground: Color.accentColor.opacity(0.15),
        hoverBackground: Color.primary.opacity(0.06),

        userBubble: Color.white.opacity(0.12),
        userBubbleText: Color(nsColor: .textColor),
        assistantBackground: Color.clear,

        composerBackground: Color(nsColor: .controlBackgroundColor),
        composerBorder: Color.secondary.opacity(0.2),
        composerBorderFocused: Color.accentColor.opacity(0.5),

        codeBackground: Color(nsColor: .textBackgroundColor).opacity(0.5),
        codeBorder: Color.primary.opacity(0.1),
        codeHeaderBackground: Color.clear,

        syntaxKeyword: Color(red: 0.78, green: 0.46, blue: 0.86),
        syntaxString: Color(red: 0.58, green: 0.79, blue: 0.49),
        syntaxComment: Color(red: 0.50, green: 0.55, blue: 0.60),
        syntaxNumber: Color(red: 0.82, green: 0.68, blue: 0.40),
        syntaxType: Color(red: 0.40, green: 0.76, blue: 0.84),
        syntaxFunction: Color(red: 0.38, green: 0.65, blue: 0.94),
        syntaxPunctuation: Color(nsColor: .textColor).opacity(0.7),
        syntaxPlain: Color(nsColor: .textColor),

        chipBackground: Color.primary.opacity(0.06),
        chipBorder: Color.primary.opacity(0.08)
    )

    /// Tokyo Night — inspired by the lights of Tokyo.
    static let tokyoNight = AppTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        isCustom: true,

        background: Color(red: 0.10, green: 0.11, blue: 0.17),         // #1a1b27
        sidebarBackground: Color(red: 0.09, green: 0.09, blue: 0.14),  // #16161e
        surfaceBackground: Color(red: 0.13, green: 0.15, blue: 0.22),  // #222436
        divider: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.6),

        textPrimary: Color(red: 0.66, green: 0.70, blue: 0.84),        // #a9b1d6
        textSecondary: Color(red: 0.45, green: 0.49, blue: 0.63),      // #737aa2
        textTertiary: Color(red: 0.33, green: 0.38, blue: 0.53),       // #565f89

        accent: Color(red: 0.49, green: 0.67, blue: 0.98),             // #7aa2f7
        selectionBackground: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.15),
        hoverBackground: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.08),

        userBubble: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.18),
        userBubbleText: Color(red: 0.66, green: 0.70, blue: 0.84),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.13, green: 0.15, blue: 0.22),
        composerBorder: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.6),
        composerBorderFocused: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.5),

        codeBackground: Color(red: 0.09, green: 0.09, blue: 0.14),     // #16161e
        codeBorder: Color(red: 0.20, green: 0.22, blue: 0.31).opacity(0.8),
        codeHeaderBackground: Color(red: 0.11, green: 0.12, blue: 0.19),

        syntaxKeyword: Color(red: 0.73, green: 0.52, blue: 0.99),      // #bb9af7
        syntaxString: Color(red: 0.60, green: 0.84, blue: 0.60),       // #9ece6a
        syntaxComment: Color(red: 0.33, green: 0.38, blue: 0.53),      // #565f89
        syntaxNumber: Color(red: 1.00, green: 0.60, blue: 0.42),       // #ff9e64
        syntaxType: Color(red: 0.17, green: 0.63, blue: 0.87),         // #2ac3de
        syntaxFunction: Color(red: 0.49, green: 0.67, blue: 0.98),     // #7aa2f7
        syntaxPunctuation: Color(red: 0.54, green: 0.59, blue: 0.74),  // #89a0c8
        syntaxPlain: Color(red: 0.66, green: 0.70, blue: 0.84),        // #a9b1d6

        chipBackground: Color(red: 0.66, green: 0.70, blue: 0.84).opacity(0.08),
        chipBorder: Color(red: 0.66, green: 0.70, blue: 0.84).opacity(0.12)
    )

    /// Tokyo Night Storm — slightly lighter background variant.
    static let tokyoNightStorm = AppTheme(
        id: "tokyo-night-storm",
        name: "Tokyo Night Storm",
        isCustom: true,

        background: Color(red: 0.14, green: 0.16, blue: 0.23),         // #24283b
        sidebarBackground: Color(red: 0.10, green: 0.11, blue: 0.17),  // #1a1b27
        surfaceBackground: Color(red: 0.17, green: 0.19, blue: 0.28),  // #2f3549
        divider: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.6),

        textPrimary: Color(red: 0.66, green: 0.70, blue: 0.84),
        textSecondary: Color(red: 0.45, green: 0.49, blue: 0.63),
        textTertiary: Color(red: 0.33, green: 0.38, blue: 0.53),

        accent: Color(red: 0.49, green: 0.67, blue: 0.98),
        selectionBackground: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.15),
        hoverBackground: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.08),

        userBubble: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.18),
        userBubbleText: Color(red: 0.66, green: 0.70, blue: 0.84),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.17, green: 0.19, blue: 0.28),
        composerBorder: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.6),
        composerBorderFocused: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.5),

        codeBackground: Color(red: 0.10, green: 0.11, blue: 0.17),
        codeBorder: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.8),
        codeHeaderBackground: Color(red: 0.13, green: 0.15, blue: 0.22),

        syntaxKeyword: Color(red: 0.73, green: 0.52, blue: 0.99),
        syntaxString: Color(red: 0.60, green: 0.84, blue: 0.60),
        syntaxComment: Color(red: 0.33, green: 0.38, blue: 0.53),
        syntaxNumber: Color(red: 1.00, green: 0.60, blue: 0.42),
        syntaxType: Color(red: 0.17, green: 0.63, blue: 0.87),
        syntaxFunction: Color(red: 0.49, green: 0.67, blue: 0.98),
        syntaxPunctuation: Color(red: 0.54, green: 0.59, blue: 0.74),
        syntaxPlain: Color(red: 0.66, green: 0.70, blue: 0.84),

        chipBackground: Color(red: 0.66, green: 0.70, blue: 0.84).opacity(0.08),
        chipBorder: Color(red: 0.66, green: 0.70, blue: 0.84).opacity(0.12)
    )

    /// Catppuccin Mocha — warm pastel dark theme.
    static let catppuccinMocha = AppTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        isCustom: true,

        background: Color(red: 0.12, green: 0.12, blue: 0.18),         // #1e1e2e  base
        sidebarBackground: Color(red: 0.10, green: 0.10, blue: 0.15),  // #181825  mantle
        surfaceBackground: Color(red: 0.14, green: 0.14, blue: 0.21),  // #242438  surface0
        divider: Color(red: 0.27, green: 0.28, blue: 0.35).opacity(0.6),

        textPrimary: Color(red: 0.80, green: 0.82, blue: 0.90),        // #cdd6f4  text
        textSecondary: Color(red: 0.58, green: 0.60, blue: 0.72),      // #9399b2  overlay2
        textTertiary: Color(red: 0.42, green: 0.44, blue: 0.55),       // #6c7086  overlay0

        accent: Color(red: 0.54, green: 0.71, blue: 0.98),             // #89b4fa  blue
        selectionBackground: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.15),
        hoverBackground: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.08),

        userBubble: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.18),
        userBubbleText: Color(red: 0.80, green: 0.82, blue: 0.90),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.14, green: 0.14, blue: 0.21),
        composerBorder: Color(red: 0.27, green: 0.28, blue: 0.35).opacity(0.6),
        composerBorderFocused: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.5),

        codeBackground: Color(red: 0.10, green: 0.10, blue: 0.15),     // #181825
        codeBorder: Color(red: 0.18, green: 0.19, blue: 0.26).opacity(0.8),
        codeHeaderBackground: Color(red: 0.12, green: 0.12, blue: 0.18),

        syntaxKeyword: Color(red: 0.80, green: 0.63, blue: 0.95),      // #cba6f7  mauve
        syntaxString: Color(red: 0.65, green: 0.89, blue: 0.63),       // #a6e3a1  green
        syntaxComment: Color(red: 0.42, green: 0.44, blue: 0.55),      // #6c7086  overlay0
        syntaxNumber: Color(red: 0.98, green: 0.70, blue: 0.53),       // #fab387  peach
        syntaxType: Color(red: 0.58, green: 0.89, blue: 0.98),         // #94e2d5  teal
        syntaxFunction: Color(red: 0.54, green: 0.71, blue: 0.98),     // #89b4fa  blue
        syntaxPunctuation: Color(red: 0.58, green: 0.60, blue: 0.72),  // #9399b2  overlay2
        syntaxPlain: Color(red: 0.80, green: 0.82, blue: 0.90),        // #cdd6f4  text

        chipBackground: Color(red: 0.80, green: 0.82, blue: 0.90).opacity(0.08),
        chipBorder: Color(red: 0.80, green: 0.82, blue: 0.90).opacity(0.12)
    )

    /// GitHub Dark — clean dark theme matching GitHub's code view.
    static let githubDark = AppTheme(
        id: "github-dark",
        name: "GitHub Dark",
        isCustom: true,

        background: Color(red: 0.06, green: 0.07, blue: 0.09),         // #0d1117
        sidebarBackground: Color(red: 0.04, green: 0.05, blue: 0.07),  // #010409
        surfaceBackground: Color(red: 0.09, green: 0.11, blue: 0.15),  // #161b22
        divider: Color(red: 0.19, green: 0.22, blue: 0.28).opacity(0.6),

        textPrimary: Color(red: 0.90, green: 0.93, blue: 0.96),        // #e6edf3
        textSecondary: Color(red: 0.56, green: 0.60, blue: 0.67),      // #8b949e
        textTertiary: Color(red: 0.38, green: 0.42, blue: 0.48),       // #636c76

        accent: Color(red: 0.34, green: 0.53, blue: 0.96),             // #58a6ff
        selectionBackground: Color(red: 0.34, green: 0.53, blue: 0.96).opacity(0.15),
        hoverBackground: Color(red: 0.34, green: 0.53, blue: 0.96).opacity(0.08),

        userBubble: Color(red: 0.22, green: 0.27, blue: 0.34),
        userBubbleText: Color(red: 0.90, green: 0.93, blue: 0.96),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.09, green: 0.11, blue: 0.15),
        composerBorder: Color(red: 0.19, green: 0.22, blue: 0.28).opacity(0.6),
        composerBorderFocused: Color(red: 0.34, green: 0.53, blue: 0.96).opacity(0.5),

        codeBackground: Color(red: 0.09, green: 0.11, blue: 0.15),     // #161b22
        codeBorder: Color(red: 0.19, green: 0.22, blue: 0.28).opacity(0.8),
        codeHeaderBackground: Color(red: 0.13, green: 0.15, blue: 0.20),

        syntaxKeyword: Color(red: 1.00, green: 0.49, blue: 0.47),      // #ff7b72
        syntaxString: Color(red: 0.63, green: 0.83, blue: 1.00),       // #a5d6ff
        syntaxComment: Color(red: 0.56, green: 0.60, blue: 0.67),      // #8b949e
        syntaxNumber: Color(red: 0.31, green: 0.69, blue: 0.98),       // #79c0ff
        syntaxType: Color(red: 1.00, green: 0.85, blue: 0.56),
        syntaxFunction: Color(red: 0.84, green: 0.73, blue: 1.00),     // #d2a8ff
        syntaxPunctuation: Color(red: 0.56, green: 0.60, blue: 0.67),
        syntaxPlain: Color(red: 0.90, green: 0.93, blue: 0.96),        // #e6edf3

        chipBackground: Color(red: 0.90, green: 0.93, blue: 0.96).opacity(0.08),
        chipBorder: Color(red: 0.90, green: 0.93, blue: 0.96).opacity(0.12)
    )

    /// All built-in themes.
    static let allThemes: [AppTheme] = [
        .system,
        .tokyoNight,
        .tokyoNightStorm,
        .catppuccinMocha,
        .githubDark,
    ]
}

// MARK: - Theme Manager (observable)

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("selected_theme_id") private var selectedThemeID: String = "system"

    @Published var current: AppTheme = .system

    private init() {
        current = AppTheme.allThemes.first(where: { $0.id == selectedThemeID }) ?? .system
    }

    func select(_ theme: AppTheme) {
        selectedThemeID = theme.id
        current = theme
    }
}

// MARK: - Environment key

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
