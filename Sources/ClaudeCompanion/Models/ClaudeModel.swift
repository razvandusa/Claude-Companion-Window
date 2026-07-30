import Foundation

/// The Claude models the companion window can talk to.
///
/// Raw values are the exact model IDs the Claude Code CLI accepts. Unknown IDs
/// decoded from disk fall back to ``defaultModel`` so a stale persisted
/// conversation never blocks the app from launching.
enum ClaudeModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case fable = "claude-fable-5"
    case opus = "claude-opus-5"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5"

    // Previous generations, kept selectable the way Claude's own "More models"
    // list keeps them.
    case opus48 = "claude-opus-4-8"
    case opus47 = "claude-opus-4-7"
    case opus46 = "claude-opus-4-6"
    case sonnet46 = "claude-sonnet-4-6"

    static let defaultModel: ClaudeModel = .opus

    var id: String { rawValue }

    /// The current generation, listed above the divider in the picker.
    static let current: [ClaudeModel] = [.fable, .opus, .sonnet, .haiku]

    /// Earlier releases, listed below the divider.
    static let previousGenerations: [ClaudeModel] = [.opus48, .opus47, .opus46, .sonnet46]

    /// Short label used in pickers and menus.
    var displayName: String {
        switch self {
        case .fable: "Fable 5"
        case .opus: "Opus 5"
        case .sonnet: "Sonnet 5"
        case .haiku: "Haiku 4.5"
        case .opus48: "Opus 4.8"
        case .opus47: "Opus 4.7"
        case .opus46: "Opus 4.6"
        case .sonnet46: "Sonnet 4.6"
        }
    }

    /// One-line description shown next to the name in Settings.
    var summary: String {
        switch self {
        case .fable: "Most capable. For the hardest reasoning and long-horizon work."
        case .opus: "Best for complex agentic work and deep reasoning."
        case .sonnet: "Balanced speed and intelligence for everyday work."
        case .haiku: "Fastest and cheapest. Best for short, simple tasks."
        case .opus48, .opus47, .opus46, .sonnet46: "Previous generation."
        }
    }

    /// `true` when the model bills against usage credits rather than the
    /// subscription this app exists to use.
    ///
    /// Surfaced as a badge in the picker, the same way Claude flags it, so
    /// choosing it is never an accident.
    var requiresUsageCredits: Bool {
        self == .fable
    }

    /// Size of the model's context window, used by the token usage indicator.
    var contextWindow: Int {
        switch self {
        case .haiku: 200_000
        default: 1_000_000
        }
    }

    /// Largest `max_tokens` the model accepts on a streaming request.
    var maximumOutputTokens: Int {
        switch self {
        case .haiku: 64_000
        default: 128_000
        }
    }

    /// Effort levels this model accepts.
    ///
    /// Not uniform: `xhigh` arrived with Opus 4.7, and Haiku 4.5 rejects the
    /// effort parameter outright — passing one anyway fails the turn.
    var supportedEfforts: [ReasoningEffort] {
        switch self {
        case .haiku:
            []
        case .opus46, .sonnet46:
            [.low, .medium, .high, .max]
        default:
            ReasoningEffort.allCases
        }
    }

    /// The nearest effort this model will accept, or `nil` when it accepts none.
    func resolvedEffort(_ requested: ReasoningEffort) -> ReasoningEffort? {
        let supported = supportedEfforts
        guard !supported.isEmpty else { return nil }
        guard !supported.contains(requested) else { return requested }
        // Step down to the highest level the model does support.
        return supported.last { $0.rank <= requested.rank } ?? supported.first
    }

    /// Name as it appears in a menu, carrying the credits warning with it —
    /// a plain menu item has nowhere else to put a badge.
    var pickerLabel: String {
        requiresUsageCredits
            ? "\(displayName) — requires usage credits"
            : displayName
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
/// Maps to the CLI's `--effort`, which accepts exactly these five levels.
enum ReasoningEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high
    /// Between `high` and `max`; shown as "Extra", matching Claude's own label.
    case xhigh
    case max

    var id: String { rawValue }

    /// Position on the ladder, used when stepping down to what a model accepts.
    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .xhigh: 3
        case .max: 4
        }
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra"
        case .max: "Max"
        }
    }

    var summary: String {
        switch self {
        case .low: "Fastest replies. Best for chat and quick lookups."
        case .medium: "Balanced. A good default for most conversations."
        case .high: "Thorough. Claude's own default."
        case .xhigh: "Deeper still. Best for coding and agentic work."
        case .max: "Most thorough. Slowest and uses your limits fastest."
        }
    }
}
