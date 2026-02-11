# AGENTS.md - Humlex macOS AI Chat App

## Project Overview
Native macOS AI chat app built with SwiftUI. Supports multiple AI providers (OpenAI, Anthropic, OpenRouter, etc.), file attachments, and MCP tools.

## Build Commands

```bash
# Build the project
swift build

# Run the app (development)
./run.sh

# Build release DMG
./build-dmg.sh [version]

# Clean build artifacts
rm -rf .build/debug .build/release
```

**Note:** This project currently has no test suite. Testing is done via manual QA.

## Project Structure

```
Views/           - SwiftUI view components
Models/          - Data models (ChatThread, ChatMessage, etc.)
Networking/      - API adapters for AI providers
Utilities/       - Helper utilities (ToastManager, ThemeManager, etc.)
Theme/           - App themes and syntax highlighting
Persistence/     - Keychain and chat persistence
Package.swift    - Swift Package Manager manifest
```

## Code Style Guidelines

### Imports
- Always import `Foundation` first
- Group imports: Foundation, Apple frameworks (SwiftUI, AppKit), external packages
- Example:
```swift
import Foundation
import SwiftUI
import AppKit
```

### File Headers
Include a standard header comment:
```swift
//
//  Filename.swift
//  AI Chat
//
//  Created by [Name] on [Date].
//
```

### Formatting
- **Indentation:** 4 spaces (no tabs)
- **Line length:** Soft wrap at ~120 characters
- **Braces:** Opening brace on same line (K&R style)
- **Trailing commas:** In multi-line arrays/dictionaries

### Naming Conventions
- **Types:** PascalCase (`ChatThread`, `LLMProviderAdapter`)
- **Variables/Functions:** camelCase (`isSending`, `fetchModels()`)
- **Enum cases:** lowercase (`case user`, `case assistant`)
- **Constants:** Lower camel case (`scrollThrottleInterval`)
- **Boolean properties:** Prefix with `is`/`has` (`isUserScrolledUp`, `hasUnreadMessages`)

### Type Declarations
- Prefer structs over classes for data models
- Use `Identifiable`, `Hashable`, `Codable` conformance where needed
- Use `let` for immutable properties, `var` for mutable
- Mark functions that modify state as `mutating` on structs

### Comments and Organization
- Use `// MARK: - Section Name` to organize files
- Document complex logic with inline comments
- Use triple-slash for public API documentation:
```swift
/// Throttles scrollTo calls to ~30fps and respects user scroll position.
private func throttledScrollToLast(proxy: ScrollViewProxy) { }
```

### SwiftUI Patterns
- Use `@AppStorage` for persisted user settings
- Use `@State` for view-local state, `@StateObject` for observable objects
- Use `@Environment` and `@EnvironmentObject` for dependency injection
- Extract complex views into private computed properties or separate structs
- Use `.onAppear`, `.onChange`, `.task` modifiers appropriately

### Error Handling
- Use Swift's `Result` type or `throws` for error propagation
- Use `do-catch` blocks for error handling
- Example:
```swift
do {
    let (data, response) = try await URLSession.shared.data(for: request)
    try validateHTTPResponse(response, data: data)
} catch {
    // Handle error
}
```

### Networking
- Use `async/await` for asynchronous operations
- Implement adapters using the `LLMProviderAdapter` protocol pattern
- Use `URLSession.shared` for HTTP requests
- Validate HTTP responses before parsing

### State Management
- Use `@AppStorage` with descriptive keys:
```swift
@AppStorage("auto_scroll_enabled") private var isAutoScrollEnabled = true
```
- Prefer explicit initializers for complex state
- Clean up timers and work items in `.onDisappear`

### Performance
- Throttle high-frequency updates (e.g., scroll events at ~30fps)
- Batch streaming text updates to reduce UI churn
- Use `LazyVStack` for long lists
- Cancel unnecessary work items and tasks

## Platform Requirements
- **macOS:** 14.0+
- **Swift:** 6.0+ (using Swift 5 language mode)
- **Minimum deployment:** macOS 14

## External Dependencies
- Sparkle (auto-updater)
- ClaudeCodeSDK (Claude Code CLI integration)

## Git Workflow
- No specific branch naming convention
- Commit messages should be concise and descriptive
- Do not commit API keys or sensitive data
