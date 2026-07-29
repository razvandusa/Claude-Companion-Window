import XCTest
@testable import ClaudeCompanion

final class ConversationTests: XCTestCase {

    func testDerivesTitleFromFirstUserMessage() {
        var conversation = Conversation()
        conversation.messages = [
            Message(role: .user, content: "How do I center a div?"),
            Message(role: .assistant, content: "Use flexbox.")
        ]

        conversation.deriveTitleIfNeeded()

        XCTAssertEqual(conversation.title, "How do I center a div?")
    }

    func testDerivedTitleIsTruncated() {
        var conversation = Conversation()
        conversation.messages = [Message(role: .user, content: String(repeating: "a", count: 120))]

        conversation.deriveTitleIfNeeded()

        XCTAssertEqual(conversation.title.count, 49) // 48 characters plus an ellipsis
        XCTAssertTrue(conversation.title.hasSuffix("…"))
    }

    func testNewlinesAreFlattenedIntoTheTitle() {
        var conversation = Conversation()
        conversation.messages = [Message(role: .user, content: "line one\nline two")]

        conversation.deriveTitleIfNeeded()

        XCTAssertEqual(conversation.title, "line one line two")
    }

    /// Retitling mid-conversation would make the header jump around.
    func testExistingTitleIsNotOverwritten() {
        var conversation = Conversation(title: "Chosen name")
        conversation.messages = [Message(role: .user, content: "something else")]

        conversation.deriveTitleIfNeeded()

        XCTAssertEqual(conversation.title, "Chosen name")
    }

    func testTitleFallsBackToAnAttachmentName() {
        let attachment = Attachment(
            filename: "diagram.png",
            kind: .image,
            mediaType: "image/png",
            data: Data()
        )
        var conversation = Conversation()
        conversation.messages = [Message(role: .user, content: "", attachments: [attachment])]

        conversation.deriveTitleIfNeeded()

        XCTAssertEqual(conversation.title, "diagram.png")
    }

    func testContextTokensComeFromTheMostRecentUsage() {
        var conversation = Conversation()
        conversation.messages = [
            Message(role: .user, content: "a"),
            Message(role: .assistant, content: "b", usage: TokenUsage(inputTokens: 10, outputTokens: 5)),
            Message(role: .user, content: "c"),
            Message(role: .assistant, content: "d", usage: TokenUsage(inputTokens: 40, outputTokens: 9))
        ]

        XCTAssertEqual(conversation.contextTokens, 49)
        XCTAssertEqual(conversation.cumulativeOutputTokens, 14)
    }

    func testCachedTokensCountTowardsContext() {
        let usage = TokenUsage(
            inputTokens: 100,
            outputTokens: 20,
            cacheReadTokens: 800,
            cacheCreationTokens: 50
        )

        XCTAssertEqual(usage.totalInputTokens, 950)
        XCTAssertEqual(usage.contextTokens, 970)
    }

    func testUnknownModelIdentifierDecodesToTheDefault() throws {
        let json = Data("\"claude-from-the-future\"".utf8)
        let model = try JSONDecoder().decode(ClaudeModel.self, from: json)
        XCTAssertEqual(model, .defaultModel)
    }

    func testMessageIsEmptyOnlyWhenNothingIsRenderable() {
        XCTAssertTrue(Message(role: .assistant).isEmpty)
        XCTAssertTrue(Message(role: .assistant, content: "  \n ").isEmpty)
        XCTAssertFalse(Message(role: .assistant, content: "text").isEmpty)
        XCTAssertFalse(Message(role: .assistant, reasoning: "thinking").isEmpty)
        XCTAssertFalse(Message(role: .assistant, errorDescription: "failed").isEmpty)
    }
}

final class ConversationStoreTests: XCTestCase {

    func testRoundTripsAConversation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConversationStore(directory: directory)
        var conversation = Conversation(title: "Saved", model: .haiku)
        conversation.messages = [
            Message(role: .user, content: "question"),
            Message(role: .assistant, content: "answer", usage: TokenUsage(inputTokens: 3, outputTokens: 4))
        ]

        try await store.save(conversation)
        let loaded = try await store.loadAll()

        XCTAssertEqual(loaded.count, 1)
        let restored = try XCTUnwrap(loaded.first)

        XCTAssertEqual(restored.id, conversation.id)
        XCTAssertEqual(restored.title, conversation.title)
        XCTAssertEqual(restored.model, conversation.model)
        XCTAssertEqual(restored.messages.map(\.id), conversation.messages.map(\.id))
        XCTAssertEqual(restored.messages.map(\.content), conversation.messages.map(\.content))
        XCTAssertEqual(restored.messages.last?.usage, conversation.messages.last?.usage)

        // Timestamps are stored as ISO-8601 with fractional seconds, so they
        // round-trip to millisecond precision rather than bit-for-bit.
        XCTAssertEqual(
            restored.updatedAt.timeIntervalSince1970,
            conversation.updatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    /// Ordering is by `updatedAt`, so whole-second precision would make two
    /// conversations saved in the same second sort arbitrarily.
    func testTimestampsKeepSubSecondPrecision() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConversationStore(directory: directory)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = Conversation(title: "earlier", updatedAt: base.addingTimeInterval(0.100))
        let later = Conversation(title: "later", updatedAt: base.addingTimeInterval(0.900))

        try await store.save(earlier)
        try await store.save(later)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.map(\.title), ["later", "earlier"])
    }

    func testLoadIsSortedNewestFirst() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConversationStore(directory: directory)
        let older = Conversation(title: "older", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = Conversation(title: "newer", updatedAt: Date(timeIntervalSince1970: 2_000))

        try await store.save(older)
        try await store.save(newer)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.map(\.title), ["newer", "older"])
    }

    /// One bad transcript must not take the whole history down with it.
    func testCorruptedFileIsQuarantinedRatherThanThrowing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConversationStore(directory: directory)
        let healthy = Conversation(title: "healthy")
        try await store.save(healthy)

        let corrupt = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: corrupt)

        let loaded = try await store.loadAll()

        XCTAssertEqual(loaded.map(\.title), ["healthy"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: corrupt.deletingPathExtension().appendingPathExtension("corrupt").path
            )
        )
    }

    func testDeleteRemovesOnlyTheNamedConversation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConversationStore(directory: directory)
        let keep = Conversation(title: "keep")
        let remove = Conversation(title: "remove")
        try await store.save(keep)
        try await store.save(remove)

        try await store.delete(id: remove.id)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.map(\.title), ["keep"])
    }

    func testDeletingAMissingConversationIsNotAnError() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConversationStore(directory: directory)
        try await store.delete(id: UUID())
    }

    // MARK: - Claude Code session

    /// Transcripts written before the CLI backend have no session fields. They
    /// must still load, and must start a fresh session rather than try to
    /// resume one that was never created.
    func testTranscriptSavedBeforeTheCLIBackendStillLoads() throws {
        let legacy = """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","title":"Old chat","messages":[],
         "model":"claude-opus-5","createdAt":760000000,"updatedAt":760000000}
        """

        let decoder = JSONDecoder()
        let conversation = try decoder.decode(Conversation.self, from: Data(legacy.utf8))

        XCTAssertEqual(conversation.title, "Old chat")
        XCTAssertFalse(conversation.hasStartedSession)
    }

    func testANewConversationGetsItsOwnSession() {
        let first = Conversation()
        let second = Conversation()

        XCTAssertNotEqual(first.sessionID, second.sessionID)
        XCTAssertFalse(first.hasStartedSession)
    }

    func testSessionSurvivesARoundTripToDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var conversation = Conversation(messages: [Message(role: .user, content: "hi")])
        conversation.hasStartedSession = true

        let store = FileConversationStore(directory: directory)
        try await store.save(conversation)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.sessionID, conversation.sessionID)
        XCTAssertEqual(loaded.first?.hasStartedSession, true)
    }
}
