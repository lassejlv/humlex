import Foundation

/// Estimates token counts for text and messages.
/// Uses character-based estimation for fast UI feedback.
/// More accurate token counting can be done via API responses.
enum TokenEstimator {
    /// Average characters per token for English text.
    /// This is a rough estimate: GPT-4 uses ~4 chars/token, Claude ~3.5-4
    static let charsPerToken: Double = 4.0
    
    /// Overhead tokens for message formatting (role markers, etc.)
    static let messageOverhead: Int = 4
    
    /// Estimates token count from character count.
    /// - Parameter text: The text to estimate
    /// - Returns: Estimated token count
    static func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return Int(Double(text.count) / charsPerToken)
    }
    
    /// Estimates token count for a chat message including attachments.
    /// - Parameter message: The chat message
    /// - Returns: Estimated token count including overhead
    static func estimateTokens(for message: ChatMessage) -> Int {
        var count = estimateTokens(for: message.text)
        
        // Add attachment content
        for attachment in message.attachments {
            count += estimateTokens(for: attachment.content)
        }
        
        // Add overhead for message structure (role markers, etc.)
        count += messageOverhead
        
        return count
    }
    
    /// Estimates total tokens for a conversation history.
    /// - Parameter messages: Array of messages
    /// - Returns: Total estimated tokens
    static func estimateTotalTokens(for messages: [ChatMessage]) -> Int {
        messages.reduce(0) { total, message in
            total + estimateTokens(for: message)
        }
    }
    
    /// Calculates remaining context window after current usage.
    /// - Parameters:
    ///   - messages: Current messages
    ///   - contextWindow: Model's context window size
    /// - Returns: Remaining tokens available
    static func remainingTokens(for messages: [ChatMessage], contextWindow: Int) -> Int {
        let used = estimateTotalTokens(for: messages)
        return max(0, contextWindow - used)
    }
    
    /// Calculates usage percentage for UI display.
    /// - Parameters:
    ///   - messages: Current messages
    ///   - contextWindow: Model's context window size
    /// - Returns: Percentage from 0.0 to 1.0
    static func usagePercentage(for messages: [ChatMessage], contextWindow: Int) -> Double {
        guard contextWindow > 0 else { return 0.0 }
        let used = estimateTotalTokens(for: messages)
        return min(1.0, Double(used) / Double(contextWindow))
    }
}

/// Tracks token usage for a thread with support for both estimated and actual values.
struct ThreadTokenUsage: Hashable, Codable {
    /// Estimated token count based on character-based calculation
    var estimatedTokens: Int
    
    /// Actual token usage from the most recent API response (if available)
    var actualTokens: Int?
    
    /// The context window size of the model
    var contextWindow: Int
    
    /// When this usage was last updated
    var lastUpdated: Date
    
    /// The percentage of context window used (based on best available data)
    var usagePercentage: Double {
        let used = actualTokens ?? estimatedTokens
        guard contextWindow > 0 else { return 0.0 }
        return min(1.0, Double(used) / Double(contextWindow))
    }
    
    /// Remaining tokens available
    var remainingTokens: Int {
        let used = actualTokens ?? estimatedTokens
        return max(0, contextWindow - used)
    }
    
    /// Whether the context window is approaching limit (>80%)
    var isNearLimit: Bool {
        usagePercentage > 0.8
    }
    
    /// Whether the context window is at risk (>90%)
    var isAtRisk: Bool {
        usagePercentage > 0.9
    }
    
    init(
        estimatedTokens: Int = 0,
        actualTokens: Int? = nil,
        contextWindow: Int,
        lastUpdated: Date = Date()
    ) {
        self.estimatedTokens = estimatedTokens
        self.actualTokens = actualTokens
        self.contextWindow = contextWindow
        self.lastUpdated = lastUpdated
    }
    
    /// Updates the estimated token count
    mutating func updateEstimated(_ tokens: Int) {
        self.estimatedTokens = tokens
        self.lastUpdated = Date()
    }
    
    /// Updates with actual token usage from API
    mutating func updateActual(_ usage: TokenUsage) {
        self.actualTokens = usage.totalTokens
        self.lastUpdated = Date()
    }
}

/// Color coding for usage levels
enum UsageLevel: String, CaseIterable {
    case normal    // < 50%
    case warning   // 50-80%
    case caution   // 80-90%
    case danger    // > 90%
    
    init(percentage: Double) {
        switch percentage {
        case ..<0.5:  self = .normal
        case ..<0.8:  self = .warning
        case ..<0.9:  self = .caution
        default:      self = .danger
        }
    }
    
    var colorName: String {
        switch self {
        case .normal:  return "green"
        case .warning: return "yellow"
        case .caution: return "orange"
        case .danger:  return "red"
        }
    }
    
    var systemColor: String {
        switch self {
        case .normal:  return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger:  return "exclamationmark.octagon.fill"
        }
    }
    
    var description: String {
        switch self {
        case .normal:  return "Plenty of space"
        case .warning: return "Getting full"
        case .caution: return "Nearly full"
        case .danger:  return "Context limit reached"
        }
    }
}
