//
//  OnboardingView.swift
//  AI Chat
//
//  Created by Codex on 19/02/2026.
//

import Foundation
import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let bullets: [String]
}

struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onGetStarted: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var currentPageIndex = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "sparkles",
            title: "Welcome to Humlex",
            subtitle: "A native macOS AI chat workspace",
            bullets: [
                "Create chats from the left sidebar.",
                "Pick your model from the composer dropdown.",
                "Use Enter to send quickly.",
            ]
        ),
        OnboardingPage(
            icon: "gearshape",
            title: "Connect Providers",
            subtitle: "Add your API keys in Settings",
            bullets: [
                "OpenAI, Anthropic, OpenRouter, Gemini, and more.",
                "Your keys are stored in macOS Keychain.",
                "Refresh models after connecting providers.",
            ]
        ),
        OnboardingPage(
            icon: "paperclip",
            title: "Use Chat + Agent",
            subtitle: "Attach files or work with tools in Agent mode",
            bullets: [
                "Paperclip adds files and images to prompts.",
                "Terminal button toggles Agent mode.",
                "Use @ for files and $ for skills in the composer.",
            ]
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                pageView(pages[currentPageIndex])
            }
            .animation(.easeInOut(duration: 0.2), value: currentPageIndex)

            footer
        }
        .frame(width: 680, height: 500)
        .background(theme.background)
    }

    private var header: some View {
        HStack {
            Text("Getting Started")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            Text("Step \(currentPageIndex + 1) of \(pages.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.hoverBackground, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: page.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(page.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(page.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accent)
                            .padding(.top, 2)
                        Text(bullet)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
            }
            .padding(16)
            .background(theme.surfaceBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.chipBorder.opacity(0.8), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Back") {
                currentPageIndex = max(0, currentPageIndex - 1)
            }
            .buttonStyle(.borderless)
            .disabled(currentPageIndex == 0)

            Spacer()

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == currentPageIndex ? theme.accent : theme.chipBorder)
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            if currentPageIndex < pages.count - 1 {
                Button("Next") {
                    currentPageIndex = min(pages.count - 1, currentPageIndex + 1)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)

                Button("Start Chatting") {
                    onGetStarted()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(theme.surfaceBackground.opacity(0.65))
    }
}
