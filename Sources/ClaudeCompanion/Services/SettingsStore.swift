import Foundation
import Combine

/// User-visible preferences, backed by `UserDefaults`.
///
/// Observed directly by the settings and chat views; every property write is
/// persisted immediately so preferences survive a force quit.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let model = "settings.model"
        static let effort = "settings.effort"
        static let thinkingEnabled = "settings.thinkingEnabled"
        static let maxTokens = "settings.maxTokens"
        static let systemPrompt = "settings.systemPrompt"
        static let dismissOnClickOutside = "settings.dismissOnClickOutside"
        static let launchAtLogin = "settings.launchAtLogin"
        static let showTokenUsage = "settings.showTokenUsage"
        static let webSearchEnabled = "settings.webSearchEnabled"
        static let panelFrame = "settings.panelFrame"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.model: ClaudeModel.defaultModel.rawValue,
            Key.effort: ReasoningEffort.medium.rawValue,
            Key.thinkingEnabled: true,
            Key.maxTokens: 16_000,
            Key.systemPrompt: "",
            Key.dismissOnClickOutside: true,
            Key.launchAtLogin: false,
            Key.showTokenUsage: true,
            Key.webSearchEnabled: false,
            Key.hasCompletedOnboarding: false
        ])

        model = ClaudeModel(rawValue: defaults.string(forKey: Key.model) ?? "") ?? .defaultModel
        effort = ReasoningEffort(rawValue: defaults.string(forKey: Key.effort) ?? "") ?? .medium
        isThinkingEnabled = defaults.bool(forKey: Key.thinkingEnabled)
        maxTokens = defaults.integer(forKey: Key.maxTokens)
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? ""
        dismissOnClickOutside = defaults.bool(forKey: Key.dismissOnClickOutside)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        showTokenUsage = defaults.bool(forKey: Key.showTokenUsage)
        isWebSearchEnabled = defaults.bool(forKey: Key.webSearchEnabled)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    @Published var model: ClaudeModel {
        didSet { defaults.set(model.rawValue, forKey: Key.model) }
    }

    @Published var effort: ReasoningEffort {
        didSet { defaults.set(effort.rawValue, forKey: Key.effort) }
    }

    /// When off, requests are sent with thinking disabled for the lowest latency.
    @Published var isThinkingEnabled: Bool {
        didSet { defaults.set(isThinkingEnabled, forKey: Key.thinkingEnabled) }
    }

    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: Key.maxTokens) }
    }

    @Published var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) }
    }

    @Published var dismissOnClickOutside: Bool {
        didSet { defaults.set(dismissOnClickOutside, forKey: Key.dismissOnClickOutside) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var showTokenUsage: Bool {
        didSet { defaults.set(showTokenUsage, forKey: Key.showTokenUsage) }
    }

    /// The globe in the composer. Grants the CLI a web-search tool for the
    /// turn; off by default, and it stays off until the user asks for it.
    @Published var isWebSearchEnabled: Bool {
        didSet { defaults.set(isWebSearchEnabled, forKey: Key.webSearchEnabled) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// `max_tokens` clamped to what the selected model actually accepts.
    var effectiveMaxTokens: Int {
        min(max(maxTokens, 1_024), model.maximumOutputTokens)
    }

    // MARK: - Panel frame

    /// Last panel position and size, restored on the next launch.
    ///
    /// Stored as a string rather than a `CGRect` so `UserDefaults` round-trips
    /// it without an archiver.
    var panelFrameDescription: String? {
        get { defaults.string(forKey: Key.panelFrame) }
        set { defaults.set(newValue, forKey: Key.panelFrame) }
    }
}
