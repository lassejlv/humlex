# Humlex

A native macOS AI chat client built with SwiftUI. Supports multiple LLM providers in a single unified interface with streaming responses, rich Markdown rendering, and syntax-highlighted code blocks.

**Zero external dependencies** -- built entirely with Apple frameworks.

## Features

- **Multi-provider support** -- OpenAI, OpenRouter, Vercel AI Gateway, and Google Gemini
- **Streaming responses** -- real-time token-by-token output via Server-Sent Events
- **Conversation threads** -- create, search, and manage multiple chat threads
- **File attachments** -- drag-and-drop images (multimodal vision) and text/code files
- **Markdown rendering** -- custom parser supporting headings, code blocks, lists, links, and inline formatting
- **Syntax highlighting** -- built-in highlighter for Swift, JavaScript/TypeScript, Python, SQL, Ruby, Bash, YAML, and more
- **Themes** -- 5 built-in themes: System, Tokyo Night, Tokyo Night Storm, Catppuccin Mocha, and GitHub Dark
- **Secure storage** -- API keys stored in the macOS Keychain
- **Chat persistence** -- conversations saved locally as JSON with debounced writes

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0+

## Build & Run

**Development:**

```sh
./run.sh
```

Builds a debug `.app` bundle and opens it.

**Release:**

```sh
./build-dmg.sh [version]
```

Builds an optimized `.app` and creates a styled `.dmg` installer (e.g., `Humlex-1.0-arm64.dmg`).

Before cutting a release tag, verify your Sparkle keypair matches the public updater key:

```sh
SPARKLE_PRIVATE_KEY="<base64-private-key>" ./scripts/verify-sparkle-keypair.sh
```

**Manual:**

```sh
swift build            # debug
swift build -c release # release
```

## Project Structure

```
AI_ChatApp.swift        App entry point and window setup
ContentView.swift       Main view: sidebar, chat area, model picker
LLMAdapter.swift        AI provider adapters and SSE streaming
ChatComposerView.swift  Message input with attachments and drag-and-drop
MessageRow.swift        Chat message display (user/assistant)
MarkdownView.swift      Markdown parser and renderer
SyntaxHighlighter.swift Token-based syntax highlighter
AppTheme.swift          Theme system and ThemeManager
SettingsView.swift      API key configuration and theme picker
KeychainStore.swift     macOS Keychain wrapper
ChatPersistence.swift   JSON-based chat history storage
ToastManager.swift      Toast notification overlay
Models.swift            Data models (threads, messages, attachments)
ProviderIcon.swift      Provider logo fetcher and cache
```

## Configuration

Open the settings panel in the app to configure API keys for each provider. Keys are stored securely in the macOS Keychain.

## License

Copyright (c) 2026 Lasse Vestergaard. All rights reserved.
