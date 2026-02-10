//
//  AI_ChatApp.swift
//  AI Chat
//
//  Created by Lasse Vestergaard on 10/02/2026.
//

import SwiftUI

@main
struct AI_ChatApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var toastManager = ToastManager.shared
    @StateObject private var appUpdater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView()
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
