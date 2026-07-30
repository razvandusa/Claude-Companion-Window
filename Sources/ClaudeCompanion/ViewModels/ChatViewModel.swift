import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Drives the conversation surface: composing, streaming, persisting.
///
/// Owns no view state beyond what the transcript and composer bind to; the
/// panel's presentation lives in ``PanelController``.
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var conversation: Conversation
    @Published private(set) var recentConversations: [Conversation] = []

    /// Text currently in the composer.
    @Published var draft: String = ""
    /// Files and images staged for the next message.
    @Published var pendingAttachments: [Attachment] = []
    /// Apps picked in "Work With". Each one contributes a capture of its
    /// frontmost window to the next message, taken at send time so the model
    /// sees the app as it is when the question is asked, not when it was added.
    @Published var workingWithApps: [CompanionApp] = []
    /// `true` while a screenshot, photo or window capture is being taken.
    @Published private(set) var isCapturing = false

    @Published private(set) var isStreaming = false
    /// Identifies the assistant message currently being written into.
    @Published private(set) var streamingMessageID: UUID?
    /// `true` between sending and the first token, so the UI can show a typing dot.
    @Published private(set) var isAwaitingFirstToken = false

    /// Non-fatal problems worth surfacing as a banner (attachment rejected, etc).
    @Published var transientMessage: String?

    /// Whether Claude Code is installed and signed in.
    @Published private(set) var status: ClaudeCodeStatus = .signedOut

    // MARK: - Collaborators

    private let settings: SettingsStore
    private let store: ConversationStoring
    private let service: ClaudeServicing
    private let statusProvider: ClaudeCodeStatusProviding
    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "Chat")

    /// Camera and screen capture are OS wrappers rather than swappable
    /// collaborators, so they are held directly instead of being injected.
    private let camera = CameraCaptureService()

    /// Set by ``AppEnvironment`` once the panel exists. Needed so the panel can
    /// step out of the way of a screenshot and so an open panel doesn't read as
    /// a click outside.
    weak var panelController: PanelController?

    private var streamTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: SettingsStore,
        store: ConversationStoring,
        service: ClaudeServicing,
        statusProvider: ClaudeCodeStatusProviding
    ) {
        self.settings = settings
        self.store = store
        self.service = service
        self.statusProvider = statusProvider
        self.conversation = Conversation(model: settings.model)

        // A model change with an untouched conversation should retitle the
        // header immediately rather than waiting for the next send.
        settings.$model
            .sink { [weak self] newModel in
                guard let self, !self.conversation.hasUserContent else { return }
                self.conversation.model = newModel
            }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    var canSend: Bool {
        !isStreaming && !isCapturing && !isComposerEmpty && status.canSend
    }

    var isComposerEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pendingAttachments.isEmpty
            && workingWithApps.isEmpty
    }

    var hasMessages: Bool { !conversation.messages.isEmpty }

    /// Approximate context used, including what's sitting in the composer.
    var estimatedContextTokens: Int {
        conversation.contextTokens + Self.estimateTokens(in: draft)
    }

    var contextWindow: Int { settings.model.contextWindow }

    /// Rough client-side token estimate. Only ever used for a progress
    /// indicator — the authoritative counts come back with each response.
    static func estimateTokens(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, text.count / 4)
    }

    // MARK: - Lifecycle

    /// Loads persisted transcripts into the history menu.
    ///
    /// The current conversation stays the empty one this view model started
    /// with: launching lands on the bare composer, not in the middle of
    /// whatever was being discussed last time. Past conversations are one
    /// click away under Recent.
    func restore() async {
        do {
            recentConversations = try await store.loadAll()
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription, privacy: .public)")
        }
        await refreshStatus()
    }

    /// Re-checks whether Claude Code is installed and signed in.
    ///
    /// Cheap but not free — it spawns `claude auth status` — so it runs on
    /// launch and when Settings closes, not on every keystroke.
    func refreshStatus() async {
        status = await statusProvider.currentStatus()
    }

    // MARK: - Conversation management

    func startNewConversation() {
        cancelStreaming()
        persistCurrentIfNeeded()

        conversation = Conversation(model: settings.model)
        draft = ""
        pendingAttachments = []
        transientMessage = nil
    }

    func open(_ target: Conversation) {
        guard target.id != conversation.id else { return }
        cancelStreaming()
        persistCurrentIfNeeded()
        conversation = target
    }

    func deleteConversation(id: UUID) {
        recentConversations.removeAll { $0.id == id }
        Task { try? await store.delete(id: id) }
        if conversation.id == id {
            conversation = Conversation(model: settings.model)
        }
    }

    // MARK: - Attachments

    func addAttachments(_ attachments: [Attachment]) {
        guard !attachments.isEmpty else { return }
        pendingAttachments.append(contentsOf: attachments)
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func apply(_ result: AttachmentLoader.Result) {
        addAttachments(result.attachments)
        if let failure = result.failureDescription {
            transientMessage = failure
        }
    }

    // MARK: - Attachment sources

    /// "Upload file" / "Upload photo".
    func presentOpenPanel(imagesOnly: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = imagesOnly ? "Choose images" : "Choose files to attach"
        if imagesOnly {
            panel.allowedContentTypes = [.image]
        }

        // The open panel takes key window status; without this the companion
        // would read that as a click outside and dismiss itself behind it.
        panelController?.beginModalPresentation()
        defer { panelController?.endModalPresentation() }

        guard panel.runModal() == .OK else { return }

        var result = AttachmentLoader.Result()
        for url in panel.urls {
            switch AttachmentLoader.loadFile(at: url) {
            case .success(let attachment): result.attachments.append(attachment)
            case .failure(let reason): result.rejected.append(reason)
            }
        }
        apply(result)
    }

    /// "Take screenshot".
    func attachScreenshot(_ mode: ScreenCaptureService.Mode) {
        guard !isCapturing else { return }
        isCapturing = true

        Task {
            // The panel steps aside so it isn't in the picture, and comes back
            // whether the capture succeeded, failed or was escaped out of.
            let outcome: ScreenCaptureService.Outcome
            if let panelController {
                outcome = await panelController.performWithPanelHidden {
                    await ScreenCaptureService.capture(mode)
                }
            } else {
                outcome = await ScreenCaptureService.capture(mode)
            }

            isCapturing = false
            handle(outcome)
        }
    }

    /// "Take photo".
    func attachCameraPhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        Task {
            do {
                let attachment = try await camera.takePhoto()
                addAttachments([attachment])
            } catch {
                transientMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isCapturing = false
        }
    }

    private func handle(_ outcome: ScreenCaptureService.Outcome) {
        switch outcome {
        case .captured(let attachment): addAttachments([attachment])
        case .cancelled: break
        case .failure(let reason): transientMessage = reason
        }
    }

    // MARK: - Work With

    func addWorkingWithApp(_ app: CompanionApp) {
        guard !workingWithApps.contains(where: { $0.id == app.id }) else { return }
        workingWithApps.append(app)
    }

    func removeWorkingWithApp(id: String) {
        workingWithApps.removeAll { $0.id == id }
    }

    func isWorkingWith(_ app: CompanionApp) -> Bool {
        workingWithApps.contains { $0.id == app.id }
    }

    // MARK: - Sending

    func send() {
        guard canSend else {
            if !status.canSend {
                transientMessage = status.remedy ?? status.summary
            }
            return
        }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        let apps = workingWithApps

        draft = ""
        pendingAttachments = []
        transientMessage = nil

        guard !apps.isEmpty else {
            dispatch(text: text, attachments: attachments)
            return
        }

        // Windows are captured now rather than when the app was picked, so the
        // model sees what the user is looking at as they ask the question.
        isCapturing = true
        Task {
            var all = attachments
            for app in apps {
                switch await ScreenCaptureService.captureWindow(of: app) {
                case .captured(let attachment): all.append(attachment)
                case .cancelled: break
                case .failure(let reason): transientMessage = reason
                }
            }
            isCapturing = false
            dispatch(text: text, attachments: all)
        }
    }

    private func dispatch(text: String, attachments: [Attachment]) {
        let userMessage = Message(role: .user, content: text, attachments: attachments)
        conversation.messages.append(userMessage)
        conversation.model = settings.model
        conversation.updatedAt = Date()

        beginAssistantTurn(sending: userMessage)
    }

    /// Records the user's verdict on a turn, or clears it when tapped again.
    func toggleFeedback(_ feedback: MessageFeedback, on messageID: UUID) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        conversation.messages[index].feedback =
            conversation.messages[index].feedback == feedback ? nil : feedback
        persistCurrentIfNeeded(immediately: true)
    }

    /// Re-runs the last turn after a failure, replacing the failed reply.
    ///
    /// The user turn is sent again. If the failed attempt got far enough for
    /// Claude Code to record it, the session will hold the question twice —
    /// harmless, and preferable to dropping the retry.
    func retryLastTurn() {
        guard !isStreaming else { return }
        guard let last = conversation.messages.last, last.role == .assistant else { return }
        conversation.messages.removeLast()
        guard let prompt = conversation.messages.last, prompt.role == .user else { return }
        beginAssistantTurn(sending: prompt)
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        finishStreaming()
    }

    // MARK: - Streaming

    private func beginAssistantTurn(sending prompt: Message) {
        let placeholder = Message(role: .assistant, model: settings.model)
        conversation.messages.append(placeholder)

        isStreaming = true
        isAwaitingFirstToken = true
        streamingMessageID = placeholder.id

        // Only the new turn goes over the wire — Claude Code holds the rest of
        // the transcript in the session and replays it on resume.
        let request = CompletionRequest(
            model: settings.model,
            message: prompt,
            sessionID: conversation.sessionID,
            isResuming: conversation.hasStartedSession,
            systemPrompt: settings.systemPrompt,
            maxTokens: settings.effectiveMaxTokens,
            effort: settings.effort,
            isWebSearchEnabled: settings.isWebSearchEnabled
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.consume(self.service.stream(request), into: placeholder.id)
        }
    }

    private func consume(
        _ stream: AsyncThrowingStream<StreamChunk, Error>,
        into messageID: UUID
    ) async {
        do {
            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                apply(chunk, to: messageID)
            }
        } catch {
            apply(error: error, to: messageID)
        }

        finishStreaming()
        conversation.deriveTitleIfNeeded()
        persistCurrentIfNeeded(immediately: true)
    }

    private func apply(_ chunk: StreamChunk, to messageID: UUID) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        switch chunk {
        case .started:
            isAwaitingFirstToken = true
            // The session now exists on disk, so every later turn — including a
            // retry of this one — resumes rather than recreates it.
            conversation.hasStartedSession = true

        case .text(let fragment):
            isAwaitingFirstToken = false
            conversation.messages[index].content += fragment
            scheduleSave()

        case .reasoning(let fragment):
            guard settings.isThinkingEnabled else { return }
            conversation.messages[index].reasoning += fragment
            scheduleSave()

        case .rateLimit(let info):
            // The quota that actually bites on a subscription.
            if let warning = info.warning { transientMessage = warning }

        case .completed(let stopReason, let usage):
            isAwaitingFirstToken = false
            conversation.messages[index].usage = usage
            conversation.messages[index].stopReason = stopReason
            if stopReason == .refusal, conversation.messages[index].content.isEmpty {
                conversation.messages[index].errorDescription =
                    "Claude declined to respond to that request."
            }
            conversation.updatedAt = Date()
        }
    }

    private func apply(error: Error, to messageID: UUID) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        logger.error("Turn failed: \(description, privacy: .public)")

        if conversation.messages[index].isEmpty {
            conversation.messages[index].errorDescription = description
        } else {
            // Partial output is worth keeping; note the interruption below it.
            conversation.messages[index].errorDescription =
                "Response interrupted: \(description)"
        }
        conversation.updatedAt = Date()
    }

    private func finishStreaming() {
        isStreaming = false
        isAwaitingFirstToken = false
        streamingMessageID = nil

        // A cancelled turn that produced nothing leaves an empty bubble behind.
        if let last = conversation.messages.last,
           last.role == .assistant,
           last.isEmpty {
            conversation.messages.removeLast()
        }
    }

    // MARK: - Persistence

    /// Coalesces the writes that would otherwise happen on every streamed token.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persistCurrentIfNeeded(immediately: Bool = false) {
        guard conversation.hasUserContent else { return }
        if immediately {
            saveTask?.cancel()
            Task { await persist() }
        } else {
            scheduleSave()
        }
    }

    private func persist() async {
        guard conversation.hasUserContent else { return }
        let snapshot = conversation
        do {
            try await store.save(snapshot)
            upsertRecent(snapshot)
        } catch {
            logger.error("Failed to save conversation: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsertRecent(_ snapshot: Conversation) {
        if let index = recentConversations.firstIndex(where: { $0.id == snapshot.id }) {
            recentConversations[index] = snapshot
        } else {
            recentConversations.insert(snapshot, at: 0)
        }
        recentConversations.sort { $0.updatedAt > $1.updatedAt }
    }
}
