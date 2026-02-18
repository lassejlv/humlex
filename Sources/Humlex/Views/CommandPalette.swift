import SwiftUI

// MARK: - Command Action

struct CommandAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let shortcut: String?
    let action: () -> Void
    
    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.action = action
    }
}

// MARK: - Command Palette View

struct CommandPalette: View {
    @Binding var isPresented: Bool
    let actions: [CommandAction]
    
    @Environment(\.appTheme) private var theme
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool
    
    private var filteredActions: [CommandAction] {
        if searchText.isEmpty {
            // Hide theme options by default, show everything else
            return actions.filter { !$0.title.hasPrefix("Theme:") }
        }
        return actions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                
                TextField("Type a command or search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.textPrimary)
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelected()
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Escape hint
                Text("esc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.chipBackground, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            theme.divider.frame(height: 1)
            
            // Actions list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                            commandRow(action, isSelected: index == selectedIndex)
                                .id(index)
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                        }
                        
                        if filteredActions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundStyle(theme.textTertiary)
                                Text("No commands found")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
    
    private func commandRow(_ action: CommandAction, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: action.icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    isSelected ? theme.accent.opacity(0.15) : theme.chipBackground,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            
            // Title & subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Shortcut
            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.chipBackground, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? theme.selectionBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < filteredActions.count {
            selectedIndex = newIndex
        }
    }
    
    private func executeSelected() {
        guard selectedIndex < filteredActions.count else { return }
        let action = filteredActions[selectedIndex]
        isPresented = false
        action.action()
    }
}

// MARK: - Command Palette Overlay

struct CommandPaletteOverlay: View {
    @Binding var isPresented: Bool
    let actions: [CommandAction]
    
    var body: some View {
        ZStack {
            if isPresented {
                // Backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }
                    .transition(.opacity)
                
                // Palette
                CommandPalette(isPresented: $isPresented, actions: actions)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isPresented)
    }
}

// MARK: - Keyboard Shortcut Modifier

struct CommandPaletteShortcutModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "k" {
                        isPresented.toggle()
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

extension View {
    func commandPaletteShortcut(isPresented: Binding<Bool>) -> some View {
        modifier(CommandPaletteShortcutModifier(isPresented: isPresented))
    }
}
