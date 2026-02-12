//
//  StatusUpdateSDK.swift
//  AI Chat
//
//  Created by Codex on 12/02/2026.
//

import Foundation

@MainActor
final class StatusUpdateSDK: ObservableObject {
    enum Level {
        case info
        case success
        case warning
        case error
    }

    struct StatusItem: Identifiable {
        let id = UUID()
        let message: String
        let source: String
        let level: Level
        let date: Date
    }

    @Published private(set) var current: StatusItem?

    private struct PersistentItem {
        var message: String
        var source: String
        var level: Level
        var date: Date
    }

    private var dismissWorkItem: DispatchWorkItem?
    private var persistentItems: [String: PersistentItem] = [:]

    func post(
        message: String,
        source: String = "System",
        level: Level = .info,
        duration: TimeInterval = 4
    ) {
        dismissWorkItem?.cancel()
        current = StatusItem(message: message, source: source, level: level, date: .now)

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.current = self.newestPersistentStatus()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func postPersistent(
        key: String,
        message: String,
        source: String = "System",
        level: Level = .info
    ) {
        let item = PersistentItem(message: message, source: source, level: level, date: .now)
        persistentItems[key] = item
        current = StatusItem(message: message, source: source, level: level, date: item.date)
    }

    func clearPersistent(key: String) {
        persistentItems.removeValue(forKey: key)
        current = newestPersistentStatus()
    }

    private func newestPersistentStatus() -> StatusItem? {
        guard let latest = persistentItems.values.max(by: { $0.date < $1.date }) else { return nil }
        return StatusItem(
            message: latest.message,
            source: latest.source,
            level: latest.level,
            date: latest.date
        )
    }
}
