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
        }
    }
}
