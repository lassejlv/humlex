import Foundation
import SwiftUI

/// Registry of experimental features that can be toggled by users.
/// Add new features by adding cases to the `Flag` enum and metadata to `featureInfo`.
enum ExperimentalFeatures {
    /// Individual experimental feature flags.
    /// Add new experimental features here as enum cases.
    enum Flag: String, CaseIterable, Identifiable, Hashable {
        /// Command palette for quick actions (⌘K)
        case commandPalette = "experimental_command_palette"
        /// Terminal panel in agent mode to view command outputs
        case terminalPanel = "experimental_terminal_panel"

        var id: String { rawValue }

        /// Filter out internal placeholder flags
        static var visibleCases: [Flag] {
            allCases.filter { !$0.rawValue.hasPrefix("_") }
        }
    }

    /// Metadata for each experimental feature
    struct FeatureInfo {
        let title: String
        let description: String
        let icon: String
        let requiresRestart: Bool

        init(
            title: String,
            description: String,
            icon: String = "flask",
            requiresRestart: Bool = false
        ) {
            self.title = title
            self.description = description
            self.icon = icon
            self.requiresRestart = requiresRestart
        }
    }

    /// Feature metadata registry - add info for each feature flag here
    private static let featureInfo: [Flag: FeatureInfo] = [
        .commandPalette: FeatureInfo(
            title: "Command Palette",
            description: "Quick access to actions and commands with ⌘K.",
            icon: "command",
            requiresRestart: false
        ),
        .terminalPanel: FeatureInfo(
            title: "Terminal Panel",
            description: "Interactive terminal at the bottom of chat in agent mode. Run commands directly.",
            icon: "terminal",
            requiresRestart: false
        ),
    ]

    /// Check if a feature is enabled
    static func isEnabled(_ flag: Flag) -> Bool {
        UserDefaults.standard.bool(forKey: flag.rawValue)
    }

    /// Enable or disable a feature
    static func setEnabled(_ flag: Flag, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: flag.rawValue)
    }

    /// Get metadata for a feature
    static func info(for flag: Flag) -> FeatureInfo {
        featureInfo[flag] ?? FeatureInfo(
            title: flag.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "No description available.",
            icon: "flask"
        )
    }

    /// Get all visible experimental features (excludes internal placeholders)
    static var allFeatures: [Flag] {
        Flag.visibleCases
    }

    /// Check if there are any experimental features available
    static var hasFeatures: Bool {
        !allFeatures.isEmpty
    }
}

/// Property wrapper for easy access to experimental feature flags in SwiftUI views
@propertyWrapper
struct ExperimentalFeature: DynamicProperty {
    @AppStorage private var isEnabled: Bool
    private let flag: ExperimentalFeatures.Flag

    init(_ flag: ExperimentalFeatures.Flag) {
        self.flag = flag
        self._isEnabled = AppStorage(wrappedValue: false, flag.rawValue)
    }

    var wrappedValue: Bool {
        get { isEnabled }
        nonmutating set { isEnabled = newValue }
    }

    var projectedValue: Binding<Bool> {
        $isEnabled
    }
}
