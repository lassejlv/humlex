//
//  AI_ChatApp.swift
//  AI Chat
//
//  Created by Lasse Vestergaard on 10/02/2026.
//

import SwiftUI
import AppKit

@main
struct AI_ChatApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var toastManager = ToastManager.shared
    @StateObject private var appUpdater = AppUpdater()

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
                .onAppear {
                    updateAppearance(for: themeManager.current)
                }
                .onReceive(themeManager.$current) { theme in
                    updateAppearance(for: theme)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
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
                          event.charactersIgnoringModifiers?.lowercased() == "q" else {
                        return event
                    }
                    terminateHumlex()
                    return nil
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

private extension View {
    func forceQuitShortcut() -> some View {
        modifier(ForceQuitShortcutModifier())
    }
}
