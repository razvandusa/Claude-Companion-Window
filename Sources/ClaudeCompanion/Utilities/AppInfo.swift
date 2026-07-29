import Foundation

/// Static identity for the app, used for logging subsystems and on-disk paths.
enum AppInfo {
    static let name = "Claude Companion"

    static let bundleIdentifier: String =
        Bundle.main.bundleIdentifier ?? "com.claudecompanion.app"

    /// Folder name under Application Support.
    static let supportDirectoryName = "ClaudeCompanion"

    static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}
