import Foundation

/// An ordered exchange with one model, persisted between launches.
struct Conversation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var messages: [Message]
    var model: ClaudeModel
    var createdAt: Date
    var updatedAt: Date

    /// Identifies the Claude Code session that holds this conversation's
    /// history. Claude Code replays the transcript itself on `--resume`, so
    /// this is what lets a chat continue across relaunches.
    var sessionID: UUID

    /// `true` once a turn has run, meaning the session exists on disk and the
    /// next turn should resume it rather than create it.
    var hasStartedSession: Bool

    init(
        id: UUID = UUID(),
        title: String = Conversation.untitled,
        messages: [Message] = [],
        model: ClaudeModel = .defaultModel,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sessionID: UUID = UUID(),
        hasStartedSession: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionID = sessionID
        self.hasStartedSession = hasStartedSession
    }

    /// Transcripts written before the CLI backend existed have neither field.
    /// They decode with a fresh session, so the next turn starts a new one
    /// rather than failing to resume a session that was never created.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([Message].self, forKey: .messages)
        model = try container.decode(ClaudeModel.self, forKey: .model)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? UUID()
        hasStartedSession = try container.decodeIfPresent(Bool.self, forKey: .hasStartedSession) ?? false
    }

    static let untitled = "New Chat"

    var isEmpty: Bool { messages.isEmpty }

    var hasUserContent: Bool { messages.contains { $0.role == .user } }

    /// Context size after the most recent assistant turn, for the usage indicator.
    var contextTokens: Int {
        messages.reversed().first(where: { $0.usage != nil })?.usage?.contextTokens ?? 0
    }

    /// Total tokens the conversation has generated, across every turn.
    var cumulativeOutputTokens: Int {
        messages.compactMap(\.usage?.outputTokens).reduce(0, +)
    }

    /// Derives a short title from the first user message.
    ///
    /// Called once, after the first turn completes — retitling on every message
    /// would make the header jitter mid-conversation.
    mutating func deriveTitleIfNeeded() {
        guard title == Self.untitled,
              let first = messages.first(where: { $0.role == .user })
        else { return }

        let source = first.content.isEmpty
            ? (first.attachments.first?.filename ?? "")
            : first.content
        let condensed = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condensed.isEmpty else { return }

        title = String(condensed.prefix(48)) + (condensed.count > 48 ? "…" : "")
    }
}
