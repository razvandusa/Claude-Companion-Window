import Foundation

/// The newline-delimited JSON that `claude --input-format stream-json
/// --output-format stream-json` reads and writes.
enum ClaudeCodeProtocol {

    // MARK: - Outgoing

    /// One user turn written to the process's stdin.
    struct UserMessage: Encodable {
        let type = "user"
        let message: Body

        struct Body: Encodable {
            let role = "user"
            let content: [ContentBlock]
        }

        init(content: [ContentBlock]) {
            self.message = Body(content: content)
        }
    }

    /// A block of user content. Images are inlined as base64, matching the
    /// Messages API shape the CLI forwards verbatim.
    enum ContentBlock: Encodable {
        case text(String)
        case image(mediaType: String, base64Data: String)

        private enum CodingKeys: String, CodingKey {
            case type, text, source
        }

        private enum SourceKeys: String, CodingKey {
            case type, mediaType = "media_type", data
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .text)
            case .image(let mediaType, let data):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(data, forKey: .data)
            }
        }
    }

    /// Builds the content blocks for one composed message.
    ///
    /// Text attachments are inlined in a `<document>` wrapper so the model can
    /// tell them apart from what the user typed; images ride along as base64.
    static func contentBlocks(for message: Message) -> [ContentBlock] {
        var blocks: [ContentBlock] = []

        for attachment in message.attachments {
            switch attachment.kind {
            case .image:
                blocks.append(.image(
                    mediaType: attachment.mediaType,
                    base64Data: attachment.data.base64EncodedString()
                ))
            case .text:
                guard let contents = attachment.textContents, !contents.isEmpty else { continue }
                blocks.append(.text(
                    "<document name=\"\(attachment.filename)\">\n\(contents)\n</document>"
                ))
            }
        }

        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(.text(message.content))
        }

        return blocks
    }

    // MARK: - Incoming

    /// One line of the CLI's output stream.
    ///
    /// Every field past `type` is optional: a single struct covers all the
    /// event kinds, and unknown kinds decode harmlessly into empty fields
    /// rather than aborting a turn that is otherwise fine.
    struct Event: Decodable {
        let type: String
        let subtype: String?
        let sessionID: String?

        /// `system`/`init` — the model the CLI actually resolved to.
        let model: String?

        /// `stream_event` — a verbatim Messages API streaming event.
        let event: StreamEvent?

        /// `rate_limit_event`
        let rateLimitInfo: RateLimitInfo?

        /// `result`
        let isError: Bool?
        let stopReason: String?
        let usage: Usage?
        let result: String?
        let totalCostUSD: Double?

        private enum CodingKeys: String, CodingKey {
            case type, subtype, model, event, result, usage
            case sessionID = "session_id"
            case rateLimitInfo = "rate_limit_info"
            case isError = "is_error"
            case stopReason = "stop_reason"
            case totalCostUSD = "total_cost_usd"
        }
    }

    /// The Messages API streaming event nested inside a `stream_event` line.
    struct StreamEvent: Decodable {
        let type: String
        let delta: Delta?
        let message: MessageStart?

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
            let stopReason: String?

            private enum CodingKeys: String, CodingKey {
                case type, text, thinking
                case stopReason = "stop_reason"
            }
        }

        struct MessageStart: Decodable {
            let model: String?
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }

        var tokenUsage: TokenUsage {
            TokenUsage(
                inputTokens: inputTokens ?? 0,
                outputTokens: outputTokens ?? 0,
                cacheReadTokens: cacheReadInputTokens ?? 0,
                cacheCreationTokens: cacheCreationInputTokens ?? 0
            )
        }
    }
}

/// Subscription quota state, reported by the CLI as the turn runs.
///
/// Only interesting to a subscription user — this is the limit that actually
/// bites, and it's the one thing an API-key client never had to show.
struct RateLimitInfo: Decodable, Equatable, Sendable {
    let status: String
    let resetsAt: TimeInterval?
    let rateLimitType: String?

    /// `true` while the account is inside its allowance.
    var isAllowed: Bool { status == "allowed" }

    /// A banner worth showing, or `nil` when there's nothing to say.
    var warning: String? {
        guard !isAllowed else { return nil }

        let window = switch rateLimitType {
        case "five_hour": "5-hour"
        case "seven_day", "weekly": "weekly"
        default: "usage"
        }

        guard let resetsAt else { return "Claude \(window) limit reached." }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let when = formatter.string(from: Date(timeIntervalSince1970: resetsAt))
        return "Claude \(window) limit reached. Resets at \(when)."
    }
}
