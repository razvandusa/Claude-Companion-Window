import Foundation

/// Everything that can go wrong on the way to a completed assistant turn.
enum ClaudeCodeError: LocalizedError, Equatable {
    /// No `claude` executable was found.
    case notInstalled
    /// Claude Code is installed but nobody is signed in.
    case signedOut
    /// The process couldn't be started at all.
    case launchFailed(String)
    /// The CLI exited non-zero without reporting a reason of its own.
    case exited(status: Int32, stderr: String)
    /// The CLI reported a failed turn.
    case turnFailed(String)
    /// The subscription's usage window is exhausted.
    case rateLimited(String)
    /// Nothing to send.
    case emptyMessage

    /// `true` for failures a retry can plausibly clear.
    var isRetryable: Bool {
        switch self {
        case .exited, .turnFailed:
            return true
        case .notInstalled, .signedOut, .launchFailed, .rateLimited, .emptyMessage:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Claude Code isn't installed, or the app can't find it. Set the path in Settings."
        case .signedOut:
            return "Not signed in to Claude Code. Run `claude auth login` in Terminal."
        case .launchFailed(let message):
            return "Couldn't start Claude Code: \(message)"
        case .exited(let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Claude Code exited with status \(status)."
                : "Claude Code failed: \(detail)"
        case .turnFailed(let message):
            return "The turn failed: \(message)"
        case .rateLimited(let message):
            return message
        case .emptyMessage:
            return "There is nothing to send."
        }
    }
}
