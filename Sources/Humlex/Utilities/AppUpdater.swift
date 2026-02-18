import AppKit
import Combine
import Foundation
import Sparkle

/// A lightweight wrapper around Sparkle's SPUStandardUpdaterController
/// for programmatic use in SwiftUI (no XIB/storyboard needed).
@MainActor
final class AppUpdater: ObservableObject {
    private let delegateProxy = SparkleUpdaterDelegateProxy()
    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?
    private var backgroundCheckTimer: Timer?
    private var hasStartedAutomaticChecks = false
    private weak var statusUpdates: StatusUpdateSDK?

    /// Whether the updater is ready to check (false while a check is already in progress).
    @Published var canCheckForUpdates = false
    @Published private(set) var latestReleaseNotesURL: URL?

    init() {
        // We perform our own startup + periodic checks and status reporting.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegateProxy,
            userDriverDelegate: nil
        )

        // Mirror the updater's canCheckForUpdates into our published property.
        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: \.canCheckForUpdates, on: self)

        delegateProxy.onDidFindValidUpdate = { [weak self] item in
            self?.latestReleaseNotesURL = item.fullReleaseNotesURL ?? item.releaseNotesURL
            self?.statusUpdates?.clearPersistent(key: "updater_check")
            self?.statusUpdates?.post(
                message: "Update available: \(item.displayVersionString)",
                source: "Updater",
                level: .success,
                duration: 8
            )
        }

        delegateProxy.onDidNotFindUpdate = { [weak self] in
            self?.latestReleaseNotesURL = nil
            self?.statusUpdates?.clearPersistent(key: "updater_check")
            self?.statusUpdates?.post(
                message: "App is up to date.",
                source: "Updater",
                level: .info,
                duration: 4
            )
        }

        delegateProxy.onDidAbortWithError = { [weak self] error in
            self?.statusUpdates?.clearPersistent(key: "updater_check")
            if self?.isNoUpdateAbort(error) == true {
                self?.latestReleaseNotesURL = nil
                self?.statusUpdates?.post(
                    message: "App is up to date.",
                    source: "Updater",
                    level: .info,
                    duration: 4
                )
            } else {
                self?.statusUpdates?.post(
                    message: "Update check failed: \(error.localizedDescription)",
                    source: "Updater",
                    level: .error,
                    duration: 8
                )
            }
        }

        updaterController.startUpdater()
        updaterController.updater.automaticallyChecksForUpdates = false
    }

    /// Trigger a user-initiated update check (shows Sparkle's built-in UI).
    func checkForUpdates() {
        statusUpdates?.post(
            message: "Checking for updates...",
            source: "Updater",
            level: .info,
            duration: 3
        )
        updaterController.checkForUpdates(nil)
    }

    var canOpenReleaseNotes: Bool {
        latestReleaseNotesURL != nil
    }

    func openLatestReleaseNotes() {
        guard let url = latestReleaseNotesURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Starts automatic silent update checks on startup and then every `interval` seconds.
    func startAutomaticChecks(statusUpdates: StatusUpdateSDK, interval: TimeInterval = 60) {
        self.statusUpdates = statusUpdates
        guard !hasStartedAutomaticChecks else { return }
        hasStartedAutomaticChecks = true

        performBackgroundCheck()

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.performBackgroundCheck()
            }
        }
        backgroundCheckTimer = timer
    }

    private func performBackgroundCheck() {
        guard canCheckForUpdates else { return }

        statusUpdates?.postPersistent(
            key: "updater_check",
            message: "Checking for updates...",
            source: "Updater",
            level: .info
        )
        updaterController.updater.checkForUpdatesInBackground()
    }

    private func isNoUpdateAbort(_ error: Error) -> Bool {
        let nsError = error as NSError
        let description = error.localizedDescription.lowercased()

        // Sparkle may sometimes surface "no update" as an abort callback.
        if description.contains("up to date")
            || description.contains("no update")
            || description.contains("no updates")
        {
            return true
        }

        // Defensive checks for known Sparkle-style domain/code pairs.
        let sparkleDomains = [
            "SUSparkleErrorDomain",
            "SUUpdaterErrorDomain",
        ]
        if sparkleDomains.contains(nsError.domain),
            [1001, 1002].contains(nsError.code)
        {
            return true
        }

        return false
    }

    /// The underlying Sparkle updater, exposed for advanced configuration if needed.
    var updater: SPUUpdater {
        updaterController.updater
    }

    deinit {
        backgroundCheckTimer?.invalidate()
    }
}

private final class SparkleUpdaterDelegateProxy: NSObject, SPUUpdaterDelegate {
    var onDidFindValidUpdate: ((SUAppcastItem) -> Void)?
    var onDidNotFindUpdate: (() -> Void)?
    var onDidAbortWithError: ((Error) -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onDidFindValidUpdate?(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        onDidNotFindUpdate?()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onDidNotFindUpdate?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        onDidAbortWithError?(error)
    }
}
