import SwiftUI

// MARK: - Theme Definition

struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String

    /// Whether this theme overrides the window chrome or uses system default.
    let isCustom: Bool
    /// For custom themes, whether the app should force dark (`true`) or light (`false`) appearance.
    let prefersDarkAppearance: Bool

    // --- App chrome ---
    let background: Color  // main chat area background
    let sidebarBackground: Color  // sidebar background
    let surfaceBackground: Color  // cards, composer, popovers
    let divider: Color  // dividers & separators

    // --- Text ---
    let textPrimary: Color  // main body text
    let textSecondary: Color  // timestamps, labels, hints
    let textTertiary: Color  // placeholder, very muted

    // --- Selection / Interactive ---
    let accent: Color  // accent / tint color
    let selectionBackground: Color  // selected list row, button highlight
    let hoverBackground: Color  // hover state on rows

    // --- Chat ---
    let userBubble: Color  // user message bubble fill
    let userBubbleText: Color  // user message text
    let assistantBackground: Color  // assistant message area (usually clear)

    // --- Composer ---
    let composerBackground: Color  // input field background
    let composerBorder: Color  // input field border
    let composerBorderFocused: Color  // input field border when focused

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
        prefersDarkAppearance: false,

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

    /// Humlex Brew — dark pine + warm amber palette inspired by the app icon.
    static let humlexBrew = AppTheme(
        id: "humlex-brew",
        name: "Humlex Brew",
        isCustom: true,
        prefersDarkAppearance: true,

        background: Color(red: 0.047, green: 0.067, blue: 0.063),  // #0c1110
        sidebarBackground: Color(red: 0.031, green: 0.051, blue: 0.043),  // #080d0b
        surfaceBackground: Color(red: 0.075, green: 0.102, blue: 0.086),  // #131a16
        divider: Color(red: 0.169, green: 0.227, blue: 0.196).opacity(0.70),  // #2b3a32

        textPrimary: Color(red: 0.957, green: 0.937, blue: 0.890),  // #f4efe3
        textSecondary: Color(red: 0.851, green: 0.796, blue: 0.694),  // #d9cbb1
        textTertiary: Color(red: 0.624, green: 0.573, blue: 0.490),  // #9f927d

        accent: Color(red: 0.122, green: 0.541, blue: 0.302),  // #1f8a4d
        selectionBackground: Color(red: 0.122, green: 0.541, blue: 0.302).opacity(0.22),
        hoverBackground: Color(red: 0.122, green: 0.541, blue: 0.302).opacity(0.12),

        userBubble: Color(red: 0.165, green: 0.176, blue: 0.192),  // #2a2d31
        userBubbleText: Color(red: 0.957, green: 0.937, blue: 0.890),  // #f4efe3
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.067, green: 0.098, blue: 0.082),  // #111915
        composerBorder: Color(red: 0.149, green: 0.180, blue: 0.165).opacity(0.75),  // #262e2a
        composerBorderFocused: Color(red: 0.169, green: 0.208, blue: 0.188).opacity(0.85),  // #2b3530

        codeBackground: Color(red: 0.059, green: 0.082, blue: 0.071),  // #0f1512
        codeBorder: Color(red: 0.149, green: 0.255, blue: 0.212).opacity(0.85),  // #264136
        codeHeaderBackground: Color(red: 0.082, green: 0.125, blue: 0.102),  // #15201a

        syntaxKeyword: Color(red: 0.957, green: 0.698, blue: 0.227),  // #f4b23a
        syntaxString: Color(red: 0.965, green: 0.894, blue: 0.702),  // #f6e4b3
        syntaxComment: Color(red: 0.431, green: 0.482, blue: 0.412),  // #6e7b69
        syntaxNumber: Color(red: 1.000, green: 0.624, blue: 0.102),  // #ff9f1a
        syntaxType: Color(red: 0.482, green: 0.812, blue: 0.612),  // #7bcf9c
        syntaxFunction: Color(red: 0.224, green: 0.663, blue: 0.420),  // #39a96b
        syntaxPunctuation: Color(red: 0.702, green: 0.667, blue: 0.588),  // #b3aa96
        syntaxPlain: Color(red: 0.957, green: 0.937, blue: 0.890),  // #f4efe3

        chipBackground: Color(red: 0.957, green: 0.937, blue: 0.890).opacity(0.08),
        chipBorder: Color(red: 0.957, green: 0.937, blue: 0.890).opacity(0.15)
    )

    /// Humlex Brew Light — bright variant of the Humlex palette.
    static let humlexBrewLight = AppTheme(
        id: "humlex-brew-light",
        name: "Humlex Brew Light",
        isCustom: true,
        prefersDarkAppearance: false,

        background: Color(red: 0.957, green: 0.945, blue: 0.910),  // #f4f1e8
        sidebarBackground: Color(red: 0.925, green: 0.906, blue: 0.859),  // #ece7db
        surfaceBackground: Color(red: 0.984, green: 0.973, blue: 0.945),  // #fbf8f1
        divider: Color(red: 0.788, green: 0.761, blue: 0.698).opacity(0.70),  // #c9c2b2

        textPrimary: Color(red: 0.106, green: 0.129, blue: 0.114),  // #1b211d
        textSecondary: Color(red: 0.259, green: 0.314, blue: 0.275),  // #425046
        textTertiary: Color(red: 0.396, green: 0.439, blue: 0.400),  // #657066

        accent: Color(red: 0.122, green: 0.541, blue: 0.302),  // #1f8a4d
        selectionBackground: Color(red: 0.122, green: 0.541, blue: 0.302).opacity(0.16),
        hoverBackground: Color(red: 0.122, green: 0.541, blue: 0.302).opacity(0.08),

        userBubble: Color(red: 0.235, green: 0.251, blue: 0.271),  // #3c4045
        userBubbleText: Color(red: 0.961, green: 0.965, blue: 0.973),  // #f5f6f8
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.969, green: 0.953, blue: 0.918),  // #f7f3ea
        composerBorder: Color(red: 0.780, green: 0.753, blue: 0.690).opacity(0.85),  // #c7c0b0
        composerBorderFocused: Color(red: 0.584, green: 0.659, blue: 0.584).opacity(0.9),  // #95a895

        codeBackground: Color(red: 0.933, green: 0.949, blue: 0.925),  // #eef2ec
        codeBorder: Color(red: 0.780, green: 0.831, blue: 0.784).opacity(0.85),  // #c7d4c8
        codeHeaderBackground: Color(red: 0.890, green: 0.918, blue: 0.875),  // #e3eadf

        syntaxKeyword: Color(red: 0.710, green: 0.416, blue: 0.000),  // #b56a00
        syntaxString: Color(red: 0.478, green: 0.353, blue: 0.133),  // #7a5a22
        syntaxComment: Color(red: 0.478, green: 0.522, blue: 0.475),  // #7a8579
        syntaxNumber: Color(red: 0.800, green: 0.431, blue: 0.110),  // #cc6e1c
        syntaxType: Color(red: 0.122, green: 0.541, blue: 0.302),  // #1f8a4d
        syntaxFunction: Color(red: 0.176, green: 0.435, blue: 0.302),  // #2d6f4d
        syntaxPunctuation: Color(red: 0.369, green: 0.400, blue: 0.369),  // #5e665e
        syntaxPlain: Color(red: 0.118, green: 0.141, blue: 0.125),  // #1e2420

        chipBackground: Color(red: 0.906, green: 0.937, blue: 0.910).opacity(0.8),  // #e7efe8
        chipBorder: Color(red: 0.808, green: 0.851, blue: 0.812).opacity(0.8)  // #ced9cf
    )

    /// Tokyo Night — inspired by the lights of Tokyo.
    static let tokyoNight = AppTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        isCustom: true,
        prefersDarkAppearance: true,

        background: Color(red: 0.10, green: 0.11, blue: 0.17),  // #1a1b27
        sidebarBackground: Color(red: 0.09, green: 0.09, blue: 0.14),  // #16161e
        surfaceBackground: Color(red: 0.13, green: 0.15, blue: 0.22),  // #222436
        divider: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.6),

        textPrimary: Color(red: 0.66, green: 0.70, blue: 0.84),  // #a9b1d6
        textSecondary: Color(red: 0.45, green: 0.49, blue: 0.63),  // #737aa2
        textTertiary: Color(red: 0.33, green: 0.38, blue: 0.53),  // #565f89

        accent: Color(red: 0.49, green: 0.67, blue: 0.98),  // #7aa2f7
        selectionBackground: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.15),
        hoverBackground: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.08),

        userBubble: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.18),
        userBubbleText: Color(red: 0.66, green: 0.70, blue: 0.84),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.13, green: 0.15, blue: 0.22),
        composerBorder: Color(red: 0.22, green: 0.24, blue: 0.34).opacity(0.6),
        composerBorderFocused: Color(red: 0.49, green: 0.67, blue: 0.98).opacity(0.5),

        codeBackground: Color(red: 0.09, green: 0.09, blue: 0.14),  // #16161e
        codeBorder: Color(red: 0.20, green: 0.22, blue: 0.31).opacity(0.8),
        codeHeaderBackground: Color(red: 0.11, green: 0.12, blue: 0.19),

        syntaxKeyword: Color(red: 0.73, green: 0.52, blue: 0.99),  // #bb9af7
        syntaxString: Color(red: 0.60, green: 0.84, blue: 0.60),  // #9ece6a
        syntaxComment: Color(red: 0.33, green: 0.38, blue: 0.53),  // #565f89
        syntaxNumber: Color(red: 1.00, green: 0.60, blue: 0.42),  // #ff9e64
        syntaxType: Color(red: 0.17, green: 0.63, blue: 0.87),  // #2ac3de
        syntaxFunction: Color(red: 0.49, green: 0.67, blue: 0.98),  // #7aa2f7
        syntaxPunctuation: Color(red: 0.54, green: 0.59, blue: 0.74),  // #89a0c8
        syntaxPlain: Color(red: 0.66, green: 0.70, blue: 0.84),  // #a9b1d6

        chipBackground: Color(red: 0.66, green: 0.70, blue: 0.84).opacity(0.08),
        chipBorder: Color(red: 0.66, green: 0.70, blue: 0.84).opacity(0.12)
    )

    /// Tokyo Night Storm — slightly lighter background variant.
    static let tokyoNightStorm = AppTheme(
        id: "tokyo-night-storm",
        name: "Tokyo Night Storm",
        isCustom: true,
        prefersDarkAppearance: true,

        background: Color(red: 0.14, green: 0.16, blue: 0.23),  // #24283b
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
        prefersDarkAppearance: true,

        background: Color(red: 0.12, green: 0.12, blue: 0.18),  // #1e1e2e  base
        sidebarBackground: Color(red: 0.10, green: 0.10, blue: 0.15),  // #181825  mantle
        surfaceBackground: Color(red: 0.14, green: 0.14, blue: 0.21),  // #242438  surface0
        divider: Color(red: 0.27, green: 0.28, blue: 0.35).opacity(0.6),

        textPrimary: Color(red: 0.80, green: 0.82, blue: 0.90),  // #cdd6f4  text
        textSecondary: Color(red: 0.58, green: 0.60, blue: 0.72),  // #9399b2  overlay2
        textTertiary: Color(red: 0.42, green: 0.44, blue: 0.55),  // #6c7086  overlay0

        accent: Color(red: 0.54, green: 0.71, blue: 0.98),  // #89b4fa  blue
        selectionBackground: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.15),
        hoverBackground: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.08),

        userBubble: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.18),
        userBubbleText: Color(red: 0.80, green: 0.82, blue: 0.90),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.14, green: 0.14, blue: 0.21),
        composerBorder: Color(red: 0.27, green: 0.28, blue: 0.35).opacity(0.6),
        composerBorderFocused: Color(red: 0.54, green: 0.71, blue: 0.98).opacity(0.5),

        codeBackground: Color(red: 0.10, green: 0.10, blue: 0.15),  // #181825
        codeBorder: Color(red: 0.18, green: 0.19, blue: 0.26).opacity(0.8),
        codeHeaderBackground: Color(red: 0.12, green: 0.12, blue: 0.18),

        syntaxKeyword: Color(red: 0.80, green: 0.63, blue: 0.95),  // #cba6f7  mauve
        syntaxString: Color(red: 0.65, green: 0.89, blue: 0.63),  // #a6e3a1  green
        syntaxComment: Color(red: 0.42, green: 0.44, blue: 0.55),  // #6c7086  overlay0
        syntaxNumber: Color(red: 0.98, green: 0.70, blue: 0.53),  // #fab387  peach
        syntaxType: Color(red: 0.58, green: 0.89, blue: 0.98),  // #94e2d5  teal
        syntaxFunction: Color(red: 0.54, green: 0.71, blue: 0.98),  // #89b4fa  blue
        syntaxPunctuation: Color(red: 0.58, green: 0.60, blue: 0.72),  // #9399b2  overlay2
        syntaxPlain: Color(red: 0.80, green: 0.82, blue: 0.90),  // #cdd6f4  text

        chipBackground: Color(red: 0.80, green: 0.82, blue: 0.90).opacity(0.08),
        chipBorder: Color(red: 0.80, green: 0.82, blue: 0.90).opacity(0.12)
    )

    /// GitHub Dark — clean dark theme matching GitHub's code view.
    static let githubDark = AppTheme(
        id: "github-dark",
        name: "GitHub Dark",
        isCustom: true,
        prefersDarkAppearance: true,

        background: Color(red: 0.06, green: 0.07, blue: 0.09),  // #0d1117
        sidebarBackground: Color(red: 0.04, green: 0.05, blue: 0.07),  // #010409
        surfaceBackground: Color(red: 0.09, green: 0.11, blue: 0.15),  // #161b22
        divider: Color(red: 0.19, green: 0.22, blue: 0.28).opacity(0.6),

        textPrimary: Color(red: 0.90, green: 0.93, blue: 0.96),  // #e6edf3
        textSecondary: Color(red: 0.56, green: 0.60, blue: 0.67),  // #8b949e
        textTertiary: Color(red: 0.38, green: 0.42, blue: 0.48),  // #636c76

        accent: Color(red: 0.34, green: 0.53, blue: 0.96),  // #58a6ff
        selectionBackground: Color(red: 0.34, green: 0.53, blue: 0.96).opacity(0.15),
        hoverBackground: Color(red: 0.34, green: 0.53, blue: 0.96).opacity(0.08),

        userBubble: Color(red: 0.22, green: 0.27, blue: 0.34),
        userBubbleText: Color(red: 0.90, green: 0.93, blue: 0.96),
        assistantBackground: Color.clear,

        composerBackground: Color(red: 0.09, green: 0.11, blue: 0.15),
        composerBorder: Color(red: 0.19, green: 0.22, blue: 0.28).opacity(0.6),
        composerBorderFocused: Color(red: 0.34, green: 0.53, blue: 0.96).opacity(0.5),

        codeBackground: Color(red: 0.09, green: 0.11, blue: 0.15),  // #161b22
        codeBorder: Color(red: 0.19, green: 0.22, blue: 0.28).opacity(0.8),
        codeHeaderBackground: Color(red: 0.13, green: 0.15, blue: 0.20),

        syntaxKeyword: Color(red: 1.00, green: 0.49, blue: 0.47),  // #ff7b72
        syntaxString: Color(red: 0.63, green: 0.83, blue: 1.00),  // #a5d6ff
        syntaxComment: Color(red: 0.56, green: 0.60, blue: 0.67),  // #8b949e
        syntaxNumber: Color(red: 0.31, green: 0.69, blue: 0.98),  // #79c0ff
        syntaxType: Color(red: 1.00, green: 0.85, blue: 0.56),
        syntaxFunction: Color(red: 0.84, green: 0.73, blue: 1.00),  // #d2a8ff
        syntaxPunctuation: Color(red: 0.56, green: 0.60, blue: 0.67),
        syntaxPlain: Color(red: 0.90, green: 0.93, blue: 0.96),  // #e6edf3

        chipBackground: Color(red: 0.90, green: 0.93, blue: 0.96).opacity(0.08),
        chipBorder: Color(red: 0.90, green: 0.93, blue: 0.96).opacity(0.12)
    )

    /// All built-in themes.
    static let allThemes: [AppTheme] = [
        .system,
        .humlexBrew,
        .humlexBrewLight,
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
