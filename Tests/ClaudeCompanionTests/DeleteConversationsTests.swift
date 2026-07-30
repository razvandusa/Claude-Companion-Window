import XCTest
@testable import ClaudeCompanion

/// Covers deleting transcripts, where the hazard is the view model writing a
/// conversation back to the store on its way out and undoing the delete.
@MainActor
final class DeleteConversationsTests: XCTestCase {

    private func makeChat(
        store: InMemoryConversationStore
    ) -> ChatViewModel {
        ChatViewModel(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "delete-tests") ?? .standard),
            store: store,
            service: PreviewClaudeService(),
            statusProvider: PreviewStatusProvider()
        )
    }

    private func makeConversation(_ text: String) -> Conversation {
        var conversation = Conversation()
        conversation.messages = [
            Message(role: .user, content: text),
            Message(role: .assistant, content: "Sure.")
        ]
        return conversation
    }

    // MARK: - Delete all

    /// Waits out the save debounce before asserting, so a queued write that
    /// lands after the delete would be caught rather than missed.
    func testDeletingEverythingDoesNotWriteTheOpenConversationBack() async throws {
        let store = InMemoryConversationStore(seed: [makeConversation("first")])
        let chat = makeChat(store: store)
        await chat.restore()

        chat.draft = "a question"
        chat.send()
        try await waitUntil { !chat.isStreaming }

        await chat.deleteAllConversations()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let remaining = try await store.loadAll()
        XCTAssertTrue(remaining.isEmpty, "delete-all left \(remaining.count) conversation(s) behind")
    }

    /// Same invariant for a single delete.
    func testDeletingTheOpenConversationSurvivesAQueuedSave() async throws {
        let store = InMemoryConversationStore()
        let chat = makeChat(store: store)

        chat.draft = "a question"
        chat.send()
        try await waitUntil { !chat.isStreaming }
        let openID = chat.conversation.id

        chat.deleteConversation(id: openID)
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let remaining = try await store.loadAll()
        XCTAssertFalse(
            remaining.contains { $0.id == openID },
            "the deleted conversation came back"
        )
    }

    /// Polls rather than sleeping a fixed amount, so the suite isn't paced by
    /// the slowest plausible turn.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out waiting for condition"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testDeletingEverythingEmptiesTheRecentsMenu() async throws {
        let store = InMemoryConversationStore(seed: [
            makeConversation("first"),
            makeConversation("second")
        ])
        let chat = makeChat(store: store)
        await chat.restore()
        XCTAssertEqual(chat.recentConversations.count, 2)

        await chat.deleteAllConversations()

        XCTAssertTrue(chat.recentConversations.isEmpty)
    }

    /// Delete-all is also the way back to an empty panel, so nothing the user
    /// had staged for the next message should survive it.
    func testDeletingEverythingClearsTheComposer() async throws {
        let store = InMemoryConversationStore()
        let chat = makeChat(store: store)

        chat.draft = "half-typed"
        chat.addAttachments([
            Attachment(filename: "a.txt", kind: .text, mediaType: "text/plain", data: Data("hi".utf8))
        ])
        chat.addWorkingWithApp(
            CompanionApp(
                id: "com.example.notes",
                name: "Notes",
                bundleURL: URL(fileURLWithPath: "/Applications/Notes.app"),
                isRunning: true,
                processIdentifier: 1
            )
        )

        await chat.deleteAllConversations()

        XCTAssertTrue(chat.draft.isEmpty)
        XCTAssertTrue(chat.pendingAttachments.isEmpty)
        XCTAssertTrue(chat.workingWithApps.isEmpty)
        XCTAssertFalse(chat.hasMessages)
    }

    // MARK: - Delete one

    func testDeletingTheOpenConversationLeavesAnEmptyOne() async throws {
        let store = InMemoryConversationStore()
        let chat = makeChat(store: store)

        chat.draft = "a question"
        chat.send()
        let openID = chat.conversation.id

        chat.deleteConversation(id: openID)

        XCTAssertNotEqual(chat.conversation.id, openID)
        XCTAssertFalse(chat.hasMessages)
        XCTAssertTrue(chat.recentConversations.isEmpty)
    }
}
