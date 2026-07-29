import Foundation

/// The Claude models the companion window can talk to.
///
/// Raw values are the exact model IDs accepted by the Anthropic Messages API.
/// Unknown IDs decoded from disk fall back to ``defaultModel`` so a stale
/// persisted conversation never blocks the app from launching.
enum ClaudeModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case opus = "claude-opus-5"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5"

    static let defaultModel: ClaudeModel = .opus

    var id: String { rawValue }

    /// Short label used in pickers and the conversation header.
    var displayName: String {
        switch self {
        case .opus: "Claude Opus"
        case .sonnet: "Claude Sonnet"
        case .haiku: "Claude Haiku"
        }
    }

    /// One-line description shown next to the name in Settings.
    var summary: String {
        switch self {
        case .opus: "Most capable. Best for hard reasoning and long tasks."
        case .sonnet: "Balanced speed and intelligence for everyday work."
        case .haiku: "Fastest and cheapest. Best for short, simple tasks."
        }
    }

    /// Size of the model's context window, used by the token usage indicator.
    var contextWindow: Int {
        switch self {
        case .opus, .sonnet: 1_000_000
        case .haiku: 200_000
        }
    }

    /// Largest `max_tokens` the model accepts on a streaming request.
    var maximumOutputTokens: Int {
        switch self {
        case .opus, .sonnet: 128_000
        case .haiku: 64_000
        }
    }

    /// `true` when the model accepts image content blocks.
    var supportsVision: Bool { true }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClaudeModel(rawValue: raw) ?? Self.defaultModel
    }
}

/// How much the model should deliberate before answering.
///
/// Maps to `output_config.effort` on the Messages API. Lower effort trades some
/// quality for markedly lower latency, which matters in a chat window.
enum ReasoningEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var summary: String {
        switch self {
        case .low: "Fastest replies. Best for chat and quick lookups."
        case .medium: "Balanced. A good default for most conversations."
        case .high: "Most thorough. Slower and uses more tokens."
        }
    }
}
