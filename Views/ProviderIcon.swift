import AppKit
import SwiftUI

/// Displays a provider logo fetched from models.dev as a template image
/// so it respects the system text/accent color.
struct ProviderIcon: View {
    let slug: String
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Placeholder while loading
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .task(id: slug) {
            image = await ProviderIconCache.shared.icon(for: slug)
        }
    }
}

/// A simple actor-based cache that fetches SVGs from models.dev
/// and converts them to template NSImages.
private actor ProviderIconCache {
    static let shared = ProviderIconCache()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func icon(for slug: String) async -> NSImage? {
        // Return cached
        if let cached = cache[slug] {
            return cached
        }

        // Join in-flight request if one exists
        if let existing = inFlight[slug] {
            return await existing.value
        }

        // Start new fetch
        let task = Task<NSImage?, Never> {
            await fetchIcon(slug: slug)
        }
        inFlight[slug] = task
        let result = await task.value
        inFlight[slug] = nil

        if let result {
            cache[slug] = result
        }
        return result
    }

    private func fetchIcon(slug: String) async -> NSImage? {
        guard let url = URL(string: "https://models.dev/logos/\(slug).svg") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                return nil
            }

            // Replace currentColor with white so the template image has visible paths
            guard var svgString = String(data: data, encoding: .utf8) else {
                return nil
            }
            svgString = svgString.replacingOccurrences(of: "currentColor", with: "white")

            guard let svgData = svgString.data(using: .utf8),
                let nsImage = NSImage(data: svgData)
            else {
                return nil
            }

            // Make it a template image so SwiftUI can tint it
            nsImage.isTemplate = true
            return nsImage
        } catch {
            return nil
        }
    }
}

// MARK: - Slug mapping

extension AIProvider {
    /// The slug used on models.dev for the provider logo.
    var iconSlug: String {
        switch self {
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        case .openRouter: return "openrouter"
        case .fastRouter: return "fastrouter"
        case .vercelAI: return "vercel"
        case .gemini: return "google"
        case .kimi: return "moonshot"
        case .ollama: return "ollama"
        case .claudeCode: return "anthropic"
        case .openAICodex: return "openai"
        }
    }
}

/// Tries to extract a provider slug from an OpenRouter-style model ID
/// like "anthropic/claude-3-haiku" -> "anthropic"
func modelIconSlug(for modelID: String) -> String? {
    guard let slash = modelID.firstIndex(of: "/") else { return nil }
    let prefix = String(modelID[modelID.startIndex..<slash]).lowercased()
    // Common known provider slugs on models.dev
    let known: Set<String> = [
        "openai", "anthropic", "google", "meta-llama", "meta", "mistralai", "mistral", "moonshot",
        "deepseek", "cohere", "microsoft", "nvidia", "perplexity", "groq",
        "x-ai", "xai", "amazon", "ai21", "databricks", "inflection",
        "nous", "qwen", "together", "fireworks",
    ]
    // Normalize some names
    let slug: String
    switch prefix {
    case "meta-llama": slug = "meta"
    case "mistralai": slug = "mistral"
    case "x-ai": slug = "xai"
    default: slug = prefix
    }
    return known.contains(slug) ? slug : nil
}
