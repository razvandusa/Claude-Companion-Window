import Combine
import Foundation
import SwiftUI

/// Composition root.
///
/// Every collaborator is injected here rather than reached for as a singleton,
/// so views and view models can be built against doubles in previews and tests.
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let conversationStore: ConversationStoring
    let service: ClaudeServicing
    let statusProvider: ClaudeCodeStatusProviding
    let chat: ChatViewModel

    /// Surfaces the composer's mic, the transcript's read-aloud button and the
    /// "Work With" picker. Held here so they outlive any one view.
    let dictation = DictationService()
    let speech = SpeechReader()
    let appDirectory = AppDirectory()

    /// Settings are presented as a sheet inside the panel rather than a separate
    /// window, so the companion stays a single surface.
    @Published var isShowingSettings = false

    /// `false` while the panel is the bare composer bar, `true` once there is a
    /// conversation to show. Drives both what ``RootView`` renders and how tall
    /// ``PanelController`` makes the window.
    @Published private(set) var isExpanded = false

    /// Height the composer wants while collapsed, measured by the view.
    /// The panel follows it so a multi-line draft grows the bar.
    @Published var collapsedContentHeight: CGFloat = 104

    /// How long the panel can stay closed before the next open starts fresh:
    /// collapsed, on a new conversation.
    static let idleResetInterval: TimeInterval = 15 * 60

    /// Set once the panel exists; used by menu commands and the header.
    weak var panelController: PanelController? {
        didSet { chat.panelController = panelController }
    }

    /// Collaborators default to `nil` rather than to a constructed value:
    /// a default argument is evaluated outside the main actor, which the
    /// `@MainActor` stores can't be.
    init(
        settings: SettingsStore? = nil,
        conversationStore: ConversationStoring? = nil,
        statusProvider: ClaudeCodeStatusProviding? = nil,
        service: ClaudeServicing? = nil
    ) {
        let settings = settings ?? SettingsStore()
        let statusProvider = statusProvider ?? ClaudeCodeStatusProvider()
        let store = conversationStore ?? FileConversationStore()
        let service = service ?? ClaudeCodeService()

        self.settings = settings
        self.conversationStore = store
        self.statusProvider = statusProvider
        self.service = service
        self.chat = ChatViewModel(
            settings: settings,
            store: store,
            service: service,
            statusProvider: statusProvider
        )

        // The panel expands the moment there is a turn to show and collapses
        // again on a new conversation — one rule, so the window can never end
        // up tall with nothing in it.
        chat.$conversation
            .map { !$0.messages.isEmpty }
            .removeDuplicates()
            .assign(to: &$isExpanded)
    }

    /// Convenience for previews: everything in memory, nothing on disk.
    static func preview() -> AppEnvironment {
        AppEnvironment(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            conversationStore: InMemoryConversationStore(),
            statusProvider: PreviewStatusProvider(),
            service: PreviewClaudeService()
        )
    }
}

/// Reports a healthy subscription login without shelling out.
struct PreviewStatusProvider: ClaudeCodeStatusProviding {
    func currentStatus() async -> ClaudeCodeStatus {
        .signedIn(account: "you@example.com", plan: "max", isSubscription: true)
    }
}

/// Emits a canned streamed reply so SwiftUI previews render a real transcript.
struct PreviewClaudeService: ClaudeServicing {
    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(model: request.model.rawValue))
                for word in "This is a preview response rendered without the network.".split(separator: " ") {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    continuation.yield(.text(String(word) + " "))
                }
                continuation.yield(.completed(
                    stopReason: .endTurn,
                    usage: TokenUsage(inputTokens: 128, outputTokens: 12)
                ))
                continuation.finish()
            }
        }
    }
}
