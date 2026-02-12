//
//  AI_ChatApp.swift
//  AI Chat
//
//  Created by Lasse Vestergaard on 10/02/2026.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    static let openModelPickerRequested = Notification.Name("openModelPickerRequested")
}

@main
struct AI_ChatApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var toastManager = ToastManager.shared
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var statusUpdates = StatusUpdateSDK()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .forceQuitShortcut()
                .overlay(alignment: .top) {
                    ToastOverlay(manager: toastManager)
                }
                .environment(\.appTheme, themeManager.current)
                .environment(\.toastManager, toastManager)
                .environmentObject(themeManager)
                .environmentObject(toastManager)
                .environmentObject(appUpdater)
                .environmentObject(statusUpdates)
                .onAppear {
                    updateAppearance(for: themeManager.current)
                }
                .onReceive(themeManager.$current) { theme in
                    updateAppearance(for: theme)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("Quit Humlex") {
                    terminateHumlex()
                }
                .keyboardShortcut("q")
            }
        }
    }
}

private func updateAppearance(for theme: AppTheme) {
    if theme.isCustom {
        // Custom themes are all dark, so force dark appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
    } else {
        // System theme: let macOS decide
        NSApp.appearance = nil
    }
}

private func terminateHumlex() {
    for window in NSApp.windows {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
    }
    NSApp.terminate(nil)
}

private struct ForceQuitShortcutModifier: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if monitor != nil { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.modifierFlags.contains(.command),
                        let key = event.charactersIgnoringModifiers?.lowercased()
                    else {
                        return event
                    }

                    if key == "q" {
                        terminateHumlex()
                        return nil
                    }

                    if key == "," {
                        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                        return nil
                    }

                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

extension View {
    fileprivate func forceQuitShortcut() -> some View {
        modifier(ForceQuitShortcutModifier())
    }
}
