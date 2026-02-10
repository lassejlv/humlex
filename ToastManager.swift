import SwiftUI

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String?
    let message: String
    let style: Style

    enum Style {
        case success
        case error
        case info
    }

    static func success(_ message: String, icon: String? = "checkmark") -> Toast {
        Toast(icon: icon, message: message, style: .success)
    }

    static func error(_ message: String, icon: String? = "xmark.circle") -> Toast {
        Toast(icon: icon, message: message, style: .error)
    }

    static func info(_ message: String, icon: String? = nil) -> Toast {
        Toast(icon: icon, message: message, style: .info)
    }
}

// MARK: - Toast Manager

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var current: Toast?

    private var dismissTask: DispatchWorkItem?

    private nonisolated init() {}

    func show(_ toast: Toast, duration: TimeInterval = 2.0) {
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            current = toast
        }

        let task = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) {
                self?.current = nil
            }
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            current = nil
        }
    }
}

// MARK: - Environment key

private struct ToastManagerKey: EnvironmentKey {
    static let defaultValue = ToastManager.shared
}

extension EnvironmentValues {
    var toastManager: ToastManager {
        get { self[ToastManagerKey.self] }
        set { self[ToastManagerKey.self] = newValue }
    }
}

// MARK: - Toast Overlay View

struct ToastOverlay: View {
    @ObservedObject var manager: ToastManager
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack {
            if let toast = manager.current {
                toastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(manager.current != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.current)
    }

    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: 8) {
            if let icon = toast.icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor(for: toast.style))
            }

            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.chipBorder, lineWidth: 1)
        )
        .onTapGesture {
            manager.dismiss()
        }
    }

    private func iconColor(for style: Toast.Style) -> Color {
        switch style {
        case .success: return .green
        case .error: return .red
        case .info: return theme.accent
        }
    }
}
