import Foundation

/// Who authored a message.
enum Role: String, Codable, Sendable {
    case user
    case assistant
}

/// Token accounting reported by the API for a single assistant turn.
struct TokenUsage: Codable, Equatable, Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0

    /// Everything the model read for this turn, cached or not.
    var totalInputTokens: Int { inputTokens + cacheReadTokens + cacheCreationTokens }

    /// Rough size of the conversation after this turn — what the context
    /// indicator shows.
    var contextTokens: Int { totalInputTokens + outputTokens }

    static let zero = TokenUsage()
}

/// Why an assistant turn stopped, for the cases the UI treats specially.
enum StopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case refusal
    case stopSequence = "stop_sequence"
    case toolUse = "tool_use"
    case pauseTurn = "pause_turn"
}

/// The user's verdict on an assistant turn, set from the action row under it.
///
/// Nothing is reported anywhere — it is a local mark, kept with the transcript
/// so a turn the user flagged still reads as flagged when they reopen it.
enum MessageFeedback: String, Codable, Sendable {
    case unhelpful
}

/// A single turn in a conversation.
///
/// `content` is the visible answer text. `reasoning` holds the model's
/// summarized thinking when the user has thinking enabled; it renders in a
/// collapsed disclosure rather than inline.
struct Message: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var role: Role
    var content: String
    var reasoning: String
    var attachments: [Attachment]
    var timestamp: Date
    var model: ClaudeModel?
    var usage: TokenUsage?
    var stopReason: StopReason?
    /// Set when the turn failed; the bubble renders an inline error with a retry affordance.
    var errorDescription: String?
    /// Set when the user marked the turn from the action row.
    var feedback: MessageFeedback?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String = "",
        reasoning: String = "",
        attachments: [Attachment] = [],
        timestamp: Date = Date(),
        model: ClaudeModel? = nil,
        usage: TokenUsage? = nil,
        stopReason: StopReason? = nil,
        errorDescription: String? = nil,
        feedback: MessageFeedback? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.attachments = attachments
        self.timestamp = timestamp
        self.model = model
        self.usage = usage
        self.stopReason = stopReason
        self.errorDescription = errorDescription
        self.feedback = feedback
    }

    /// `true` when there is nothing at all to render for this message yet.
    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reasoning.isEmpty
            && attachments.isEmpty
            && errorDescription == nil
    }

    /// Plain-text form used by "Copy message" and the share menu.
    var plainText: String {
        var parts: [String] = []
        if !attachments.isEmpty {
            parts.append(attachments.map { "[\($0.filename)]" }.joined(separator: " "))
        }
        if !content.isEmpty { parts.append(content) }
        return parts.joined(separator: "\n")
    }
}
