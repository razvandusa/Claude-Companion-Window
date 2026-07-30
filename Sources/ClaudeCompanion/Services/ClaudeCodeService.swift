import Foundation
import OSLog

/// A single request for one assistant turn.
///
/// Unlike an API client, this carries only the *new* user turn: Claude Code
/// owns the transcript and replays it itself when the session is resumed.
struct CompletionRequest: Sendable {
    var model: ClaudeModel
    /// The user turn to send.
    var message: Message
    /// Identifies the Claude Code session backing this conversation.
    var sessionID: UUID
    /// `false` on the first turn, which creates the session.
    var isResuming: Bool
    var systemPrompt: String
    var maxTokens: Int
    var effort: ReasoningEffort
    /// Set by the globe in the composer. The only tool this window ever grants.
    var isWebSearchEnabled: Bool = false
}

/// Incremental output from a streaming turn.
enum StreamChunk: Sendable, Equatable {
    /// Emitted once, when the CLI names the serving model.
    case started(model: String)
    /// A fragment of the visible answer.
    case text(String)
    /// A fragment of the summarized reasoning.
    case reasoning(String)
    /// Subscription quota state, reported mid-turn.
    case rateLimit(RateLimitInfo)
    /// Final accounting, emitted once at the end of a successful turn.
    case completed(stopReason: StopReason?, usage: TokenUsage)
}

/// Streams one assistant turn.
protocol ClaudeServicing: Sendable {
    /// Cancelling the consuming task terminates the underlying process.
    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<StreamChunk, Error>
}

/// Drives the `claude` CLI in headless streaming mode.
///
/// This is what makes the companion bill against a Claude subscription rather
/// than API credits: Claude Code authenticates with the OAuth login from
/// `claude auth login`, and this process inherits it.
struct ClaudeCodeService: ClaudeServicing {
    private let locator: ClaudeCodeLocating
    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "ClaudeCode")

    init(locator: ClaudeCodeLocating = ClaudeCodeLocator()) {
        self.locator = locator
    }

    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Process

    private func run(
        _ request: CompletionRequest,
        into continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    ) async throws {
        guard let executable = locator.locate() else { throw ClaudeCodeError.notInstalled }

        let blocks = ClaudeCodeProtocol.contentBlocks(for: request.message)
        guard !blocks.isEmpty else { throw ClaudeCodeError.emptyMessage }

        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(for: request)
        process.currentDirectoryURL = ClaudeCodeWorkspace.directory
        process.environment = Self.environment(maxTokens: request.maxTokens)

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let collectedErrors = ErrorOutput()
        errors.fileHandleForReading.readabilityHandler = { handle in
            collectedErrors.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            errors.fileHandleForReading.readabilityHandler = nil
            throw ClaudeCodeError.launchFailed(error.localizedDescription)
        }

        // Write the turn, then close stdin — that's what tells the CLI the
        // user's message is complete and it should start generating.
        let payload = try JSONEncoder().encode(ClaudeCodeProtocol.UserMessage(content: blocks))
        try? input.fileHandleForWriting.write(contentsOf: payload + Data("\n".utf8))
        try? input.fileHandleForWriting.close()

        defer {
            errors.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }

        try await withTaskCancellationHandler {
            try await consume(
                output.fileHandleForReading,
                process: process,
                errors: collectedErrors,
                into: continuation
            )
        } onCancel: {
            // A blocking read won't notice task cancellation; killing the
            // child is what actually unblocks it.
            process.terminate()
        }
    }

    private func consume(
        _ handle: FileHandle,
        process: Process,
        errors: ErrorOutput,
        into continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    ) async throws {
        let decoder = JSONDecoder()
        var usage = TokenUsage.zero
        var stopReason: StopReason?
        var didComplete = false

        for try await line in handle.bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }

            let event: ClaudeCodeProtocol.Event
            do {
                event = try decoder.decode(ClaudeCodeProtocol.Event.self, from: data)
            } catch {
                // Forward compatibility: a line shape this client doesn't model
                // yet must not abort a turn that is otherwise fine.
                logger.debug("Ignoring undecodable line: \(line, privacy: .public)")
                continue
            }

            switch event.type {
            case "system":
                guard event.subtype == "init" else { break }
                continuation.yield(.started(model: event.model ?? ""))

            case "stream_event":
                guard let inner = event.event else { break }
                switch inner.type {
                case "content_block_delta":
                    if let text = inner.delta?.text, !text.isEmpty {
                        continuation.yield(.text(text))
                    } else if let thinking = inner.delta?.thinking, !thinking.isEmpty {
                        continuation.yield(.reasoning(thinking))
                    }
                case "message_delta":
                    if let raw = inner.delta?.stopReason {
                        stopReason = StopReason(rawValue: raw)
                    }
                default:
                    break // message_start/stop, content_block_start/stop, ping
                }

            case "rate_limit_event":
                if let info = event.rateLimitInfo {
                    continuation.yield(.rateLimit(info))
                }

            case "result":
                usage = event.usage?.tokenUsage ?? usage
                if let raw = event.stopReason { stopReason = StopReason(rawValue: raw) }

                if event.isError == true {
                    throw ClaudeCodeError.turnFailed(
                        event.result ?? event.subtype ?? "Claude Code reported a failed turn."
                    )
                }

                continuation.yield(.completed(stopReason: stopReason, usage: usage))
                didComplete = true

            default:
                break // assistant/user echoes — already covered by the deltas
            }
        }

        process.waitUntilExit()
        guard !didComplete else { return }

        try Task.checkCancellation()

        if process.terminationStatus != 0 {
            throw ClaudeCodeError.exited(
                status: process.terminationStatus,
                stderr: errors.text
            )
        }

        // Stream ended without a result line — treat what arrived as final.
        continuation.yield(.completed(stopReason: stopReason, usage: usage))
    }

    // MARK: - Invocation

    static func arguments(for request: CompletionRequest) -> [String] {
        var arguments = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--model", request.model.rawValue,
            // This is a chat window, not a coding agent: no MCP servers, no
            // skills, and our own system prompt in place of the agent one. The
            // tool list stays empty unless the user lit the globe, and even
            // then it grants search and nothing that touches their machine.
            "--tools", request.isWebSearchEnabled ? Self.webSearchTool : "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--system-prompt", systemPrompt(
                request.systemPrompt,
                isWebSearchEnabled: request.isWebSearchEnabled
            )
        ]

        // Effort isn't universal: `xhigh` arrived with Opus 4.7, and Haiku 4.5
        // rejects the flag outright. Send the nearest level the chosen model
        // accepts, or omit it entirely.
        if let effort = request.model.resolvedEffort(request.effort) {
            arguments += ["--effort", effort.rawValue]
        }

        let session = request.sessionID.uuidString.lowercased()
        arguments += request.isResuming ? ["--resume", session] : ["--session-id", session]

        return arguments
    }

    /// The one tool the composer's globe can turn on.
    static let webSearchTool = "WebSearch"

    /// Replaces Claude Code's coding-agent prompt, then appends whatever the
    /// user set in Settings.
    static func systemPrompt(_ custom: String, isWebSearchEnabled: Bool = false) -> String {
        let capabilities = isWebSearchEnabled
            ? """
            You can search the web, and that is your only tool — you have no access \
            to the user's files or shell. Search when the answer depends on current \
            information, and cite the sources you used.
            """
            : """
            You have no tools and no access to the user's files, shell, or network — \
            answer from what you know and from what the user gives you in the conversation.
            """

        let base = """
        You are Claude, answering in a small floating companion window on macOS. \
        Reply in Markdown. Be direct and concise, and skip preamble. \
        \(capabilities)
        """

        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : base + "\n\n" + trimmed
    }

    /// The child's environment.
    ///
    /// `ANTHROPIC_API_KEY` is stripped deliberately. Claude Code prefers a key
    /// from the environment over the OAuth login, so leaving one in scope would
    /// silently move usage back onto API credits — the exact thing this app
    /// exists to avoid.
    static func environment(maxTokens: Int) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        environment.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
        environment["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] = String(maxTokens)
        return environment
    }
}

/// Accumulates the child's stderr off the reading thread.
private final class ErrorOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        // Bounded: a misbehaving child must not stream stderr into memory.
        guard data.count < 64 * 1024 else { return }
        data.append(chunk)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
