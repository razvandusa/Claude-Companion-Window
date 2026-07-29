import XCTest
@testable import ClaudeCompanion

/// Covers decoding of the CLI's newline-delimited output stream.
///
/// The fixtures are lines captured verbatim from `claude --output-format
/// stream-json`, trimmed only of fields this client doesn't read.
final class ClaudeCodeStreamTests: XCTestCase {

    private func decode(_ json: String) throws -> ClaudeCodeProtocol.Event {
        try JSONDecoder().decode(
            ClaudeCodeProtocol.Event.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - Session start

    func testInitLineReportsTheResolvedModelAndSession() throws {
        let event = try decode("""
        {"type":"system","subtype":"init","session_id":"cb3cf055-0b79-498f-965e-00ae97400797",
         "model":"claude-sonnet-5","apiKeySource":"none","claude_code_version":"2.1.220"}
        """)

        XCTAssertEqual(event.type, "system")
        XCTAssertEqual(event.subtype, "init")
        XCTAssertEqual(event.model, "claude-sonnet-5")
        XCTAssertEqual(event.sessionID, "cb3cf055-0b79-498f-965e-00ae97400797")
    }

    // MARK: - Deltas

    func testTextDeltaCarriesTheFragment() throws {
        let event = try decode("""
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,
         "delta":{"type":"text_delta","text":"pong"}},"session_id":"abc"}
        """)

        XCTAssertEqual(event.event?.type, "content_block_delta")
        XCTAssertEqual(event.event?.delta?.text, "pong")
        XCTAssertNil(event.event?.delta?.thinking)
    }

    func testThinkingDeltaIsDistinguishableFromVisibleText() throws {
        let event = try decode("""
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,
         "delta":{"type":"thinking_delta","thinking":"Let me check."}},"session_id":"abc"}
        """)

        XCTAssertEqual(event.event?.delta?.thinking, "Let me check.")
        XCTAssertNil(event.event?.delta?.text)
    }

    func testMessageDeltaCarriesTheStopReason() throws {
        let event = try decode("""
        {"type":"stream_event","event":{"type":"message_delta",
         "delta":{"stop_reason":"end_turn","stop_sequence":null}},"session_id":"abc"}
        """)

        XCTAssertEqual(event.event?.delta?.stopReason, "end_turn")
        XCTAssertEqual(StopReason(rawValue: "end_turn"), .endTurn)
    }

    // MARK: - Result

    func testSuccessfulResultCarriesUsageAndStopReason() throws {
        let event = try decode("""
        {"type":"result","subtype":"success","is_error":false,"stop_reason":"end_turn",
         "result":"pong","total_cost_usd":0.010246,
         "usage":{"input_tokens":2,"cache_creation_input_tokens":1598,
                  "cache_read_input_tokens":0,"output_tokens":4}}
        """)

        XCTAssertEqual(event.isError, false)
        XCTAssertEqual(event.stopReason, "end_turn")

        let usage = try XCTUnwrap(event.usage?.tokenUsage)
        XCTAssertEqual(usage.inputTokens, 2)
        XCTAssertEqual(usage.outputTokens, 4)
        XCTAssertEqual(usage.cacheCreationTokens, 1598)
        XCTAssertEqual(usage.totalInputTokens, 1600)
    }

    func testFailedResultIsFlaggedAndCarriesADescription() throws {
        let event = try decode("""
        {"type":"result","subtype":"error_during_execution","is_error":true,
         "result":"Credit balance is too low","stop_reason":null}
        """)

        XCTAssertEqual(event.isError, true)
        XCTAssertEqual(event.result, "Credit balance is too low")
    }

    // MARK: - Robustness

    /// Fields this client doesn't model must not abort a turn that is fine.
    func testUnknownFieldsAndEventTypesDecodeWithoutThrowing() throws {
        let event = try decode("""
        {"type":"some_future_event","brand_new_field":{"nested":[1,2,3]},
         "another":null,"session_id":"abc"}
        """)

        XCTAssertEqual(event.type, "some_future_event")
        XCTAssertNil(event.event)
        XCTAssertNil(event.usage)
    }

    /// Emitted alongside the deltas; ignoring it must not break the turn.
    func testAssistantEchoDecodesButCarriesNoDeltaToDuplicate() throws {
        let event = try decode("""
        {"type":"assistant","message":{"model":"claude-sonnet-5","role":"assistant",
         "content":[{"type":"text","text":"pong"}]},"session_id":"abc"}
        """)

        XCTAssertEqual(event.type, "assistant")
        XCTAssertNil(event.event)
    }

    // MARK: - Rate limits

    func testAllowedRateLimitProducesNoWarning() throws {
        let event = try decode("""
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed",
         "resetsAt":1785285000,"rateLimitType":"five_hour"}}
        """)

        let info = try XCTUnwrap(event.rateLimitInfo)
        XCTAssertTrue(info.isAllowed)
        XCTAssertNil(info.warning)
    }

    func testExhaustedRateLimitNamesTheWindowAndTheResetTime() throws {
        let event = try decode("""
        {"type":"rate_limit_event","rate_limit_info":{"status":"rejected",
         "resetsAt":1785285000,"rateLimitType":"five_hour"}}
        """)

        let info = try XCTUnwrap(event.rateLimitInfo)
        XCTAssertFalse(info.isAllowed)
        let warning = try XCTUnwrap(info.warning)
        XCTAssertTrue(warning.contains("5-hour"))
        XCTAssertTrue(warning.contains("Resets at"))
    }

    func testRateLimitWithoutAResetTimeStillWarns() {
        let info = RateLimitInfo(status: "rejected", resetsAt: nil, rateLimitType: "seven_day")
        XCTAssertEqual(info.warning, "Claude weekly limit reached.")
    }
}

/// Covers how install and sign-in state is presented.
final class ClaudeCodeStatusTests: XCTestCase {

    func testOnlyASignedInStatusCanSend() {
        XCTAssertTrue(
            ClaudeCodeStatus.signedIn(account: "a@b.com", plan: "pro", isSubscription: true).canSend
        )
        XCTAssertFalse(ClaudeCodeStatus.signedOut.canSend)
        XCTAssertFalse(ClaudeCodeStatus.notInstalled.canSend)
    }

    func testSubscriptionLoginNamesThePlan() {
        let status = ClaudeCodeStatus.signedIn(account: "a@b.com", plan: "max", isSubscription: true)
        XCTAssertEqual(status.summary, "Signed in as a@b.com on Claude Max.")
        XCTAssertNil(status.remedy)
    }

    /// Claude Code running on an API key is a working setup, but not the one
    /// this app is for — say so rather than showing a bare success.
    func testAPIKeyLoginIsCalledOut() {
        let status = ClaudeCodeStatus.signedIn(account: "a@b.com", plan: nil, isSubscription: false)
        XCTAssertTrue(status.summary.contains("API credits"))
    }

    func testUnusableStatesExplainWhatToDo() {
        XCTAssertNotNil(ClaudeCodeStatus.signedOut.remedy)
        XCTAssertNotNil(ClaudeCodeStatus.notInstalled.remedy)
    }
}
