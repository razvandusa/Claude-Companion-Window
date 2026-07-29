import XCTest
@testable import ClaudeCompanion

/// Covers how a turn is handed to the `claude` CLI: the argument list, the
/// child environment, and the JSON written to its stdin.
final class ClaudeCodeInvocationTests: XCTestCase {

    private func makeRequest(
        message: Message = Message(role: .user, content: "hello"),
        isResuming: Bool = false,
        sessionID: UUID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!,
        systemPrompt: String = "",
        maxTokens: Int = 16_000,
        model: ClaudeModel = .sonnet,
        effort: ReasoningEffort = .medium
    ) -> CompletionRequest {
        CompletionRequest(
            model: model,
            message: message,
            sessionID: sessionID,
            isResuming: isResuming,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            effort: effort
        )
    }

    /// Reads the value following a flag, so assertions don't depend on order.
    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    // MARK: - Arguments

    func testFirstTurnCreatesASessionAndLaterTurnsResumeIt() {
        let sessionID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

        let first = ClaudeCodeService.arguments(for: makeRequest(isResuming: false, sessionID: sessionID))
        XCTAssertEqual(value(after: "--session-id", in: first), sessionID.uuidString.lowercased())
        XCTAssertFalse(first.contains("--resume"))

        let second = ClaudeCodeService.arguments(for: makeRequest(isResuming: true, sessionID: sessionID))
        XCTAssertEqual(value(after: "--resume", in: second), sessionID.uuidString.lowercased())
        XCTAssertFalse(second.contains("--session-id"))
    }

    func testModelAndEffortArePassedThrough() {
        let arguments = ClaudeCodeService.arguments(
            for: makeRequest(model: .opus, effort: .high)
        )
        XCTAssertEqual(value(after: "--model", in: arguments), ClaudeModel.opus.rawValue)
        XCTAssertEqual(value(after: "--effort", in: arguments), "high")
    }

    func testStreamingFlagsAreSet() {
        let arguments = ClaudeCodeService.arguments(for: makeRequest())
        XCTAssertTrue(arguments.contains("--print"))
        XCTAssertTrue(arguments.contains("--include-partial-messages"))
        XCTAssertEqual(value(after: "--input-format", in: arguments), "stream-json")
        XCTAssertEqual(value(after: "--output-format", in: arguments), "stream-json")
    }

    /// A chat window must not inherit the coding agent's reach.
    func testAgentCapabilitiesAreDisabled() {
        let arguments = ClaudeCodeService.arguments(for: makeRequest())
        XCTAssertEqual(value(after: "--tools", in: arguments), "")
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertTrue(arguments.contains("--disable-slash-commands"))
    }

    /// The globe is the only thing that can widen what the window may do, and
    /// it grants search — never anything that reaches the user's machine.
    func testWebSearchIsTheOnlyToolTheGlobeGrants() {
        var request = makeRequest()
        request.isWebSearchEnabled = true

        let arguments = ClaudeCodeService.arguments(for: request)
        XCTAssertEqual(value(after: "--tools", in: arguments), "WebSearch")
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertTrue(arguments.contains("--disable-slash-commands"))
    }

    func testToolsStayEmptyWhenWebSearchIsOff() {
        let arguments = ClaudeCodeService.arguments(for: makeRequest())
        XCTAssertEqual(value(after: "--tools", in: arguments), "")
    }

    // MARK: - System prompt

    func testSystemPromptReplacesTheAgentPromptEvenWhenTheUserSetNone() {
        let prompt = ClaudeCodeService.systemPrompt("")
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains("no tools"))
    }

    func testCustomSystemPromptIsAppendedRatherThanReplacing() {
        let prompt = ClaudeCodeService.systemPrompt("Always answer in French.")
        XCTAssertTrue(prompt.contains("Always answer in French."))
        XCTAssertTrue(prompt.hasPrefix(ClaudeCodeService.systemPrompt("")))
    }

    /// Telling the model it has no tools while handing it one is the fastest
    /// way to get a refusal to search.
    func testSystemPromptStopsClaimingThereAreNoToolsOnceSearchIsOn() {
        let prompt = ClaudeCodeService.systemPrompt("", isWebSearchEnabled: true)
        XCTAssertFalse(prompt.contains("no tools"))
        XCTAssertTrue(prompt.contains("search the web"))
    }

    func testCustomPromptIsStillAppendedWithSearchOn() {
        let prompt = ClaudeCodeService.systemPrompt(
            "Always answer in French.",
            isWebSearchEnabled: true
        )
        XCTAssertTrue(prompt.hasSuffix("Always answer in French."))
    }

    func testWhitespaceOnlySystemPromptIsIgnored() {
        XCTAssertEqual(ClaudeCodeService.systemPrompt("   \n  "), ClaudeCodeService.systemPrompt(""))
    }

    // MARK: - Environment

    /// The whole point of the CLI backend: an API key in scope would send usage
    /// back to API credits instead of the subscription.
    func testAPIKeyIsStrippedFromTheChildEnvironment() {
        let environment = ClaudeCodeService.environment(maxTokens: 8_000)
        XCTAssertNil(environment["ANTHROPIC_API_KEY"])
        XCTAssertNil(environment["ANTHROPIC_AUTH_TOKEN"])
    }

    func testMaxTokensIsPassedAsAnEnvironmentVariable() {
        let environment = ClaudeCodeService.environment(maxTokens: 8_000)
        XCTAssertEqual(environment["CLAUDE_CODE_MAX_OUTPUT_TOKENS"], "8000")
    }

    // MARK: - Outgoing content blocks

    func testPlainTextBecomesASingleTextBlock() throws {
        let message = Message(role: .user, content: "What is 2 + 2?")
        let json = try encodedBlocks(for: message)

        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["type"] as? String, "text")
        XCTAssertEqual(json[0]["text"] as? String, "What is 2 + 2?")
    }

    func testImageAttachmentsAreInlinedAsBase64BeforeTheText() throws {
        let image = Attachment(
            filename: "shot.png",
            kind: .image,
            mediaType: "image/png",
            data: Data([0x01, 0x02, 0x03])
        )
        let message = Message(role: .user, content: "What is this?", attachments: [image])
        let json = try encodedBlocks(for: message)

        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["type"] as? String, "image")
        let source = try XCTUnwrap(json[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, Data([0x01, 0x02, 0x03]).base64EncodedString())
        XCTAssertEqual(json[1]["type"] as? String, "text")
    }

    func testTextAttachmentsAreWrappedSoTheyAreDistinguishableFromTheUsersOwnWords() throws {
        let note = Attachment(
            filename: "notes.txt",
            kind: .text,
            mediaType: "text/plain",
            data: Data("remember the milk".utf8)
        )
        let message = Message(role: .user, content: "Summarize", attachments: [note])
        let json = try encodedBlocks(for: message)

        let document = try XCTUnwrap(json[0]["text"] as? String)
        XCTAssertTrue(document.contains("<document name=\"notes.txt\">"))
        XCTAssertTrue(document.contains("remember the milk"))
    }

    func testAMessageWithNothingToSendProducesNoBlocks() {
        let empty = Message(role: .user, content: "   \n ")
        XCTAssertTrue(ClaudeCodeProtocol.contentBlocks(for: empty).isEmpty)
    }

    func testUserMessageEnvelopeMatchesTheCLIsExpectedShape() throws {
        let payload = ClaudeCodeProtocol.UserMessage(content: [.text("hi")])
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["type"] as? String, "user")
        let message = try XCTUnwrap(json["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
        XCTAssertNotNil(message["content"] as? [[String: Any]])
    }

    private func encodedBlocks(for message: Message) throws -> [[String: Any]] {
        let blocks = ClaudeCodeProtocol.contentBlocks(for: message)
        let data = try JSONEncoder().encode(blocks)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}
