import Foundation
import Sparkle
import Combine

/// A lightweight wrapper around Sparkle's SPUStandardUpdaterController
/// for programmatic use in SwiftUI (no XIB/storyboard needed).
@MainActor
final class AppUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    /// Whether the updater is ready to check (false while a check is already in progress).
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → Sparkle begins its automatic periodic check on launch.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Mirror the updater's canCheckForUpdates into our published property.
        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    /// Trigger a user-initiated update check (shows Sparkle's built-in UI).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// The underlying Sparkle updater, exposed for advanced configuration if needed.
    var updater: SPUUpdater {
        updaterController.updater
    }
}
