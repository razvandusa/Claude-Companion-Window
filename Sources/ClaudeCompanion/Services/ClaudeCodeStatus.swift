import Foundation

/// Whether the companion can talk to Claude, and on whose account.
enum ClaudeCodeStatus: Equatable, Sendable {
    /// Signed in. `plan` is the subscription tier when there is one — a Claude
    /// account rather than API credits.
    case signedIn(account: String?, plan: String?, isSubscription: Bool)
    /// Claude Code is installed but nobody is signed in.
    case signedOut
    /// No `claude` executable could be found.
    case notInstalled

    var canSend: Bool {
        if case .signedIn = self { return true }
        return false
    }

    /// One-line summary for Settings and the empty-state banner.
    var summary: String {
        switch self {
        case .signedIn(let account, let plan, let isSubscription):
            let who = account ?? "your Claude account"
            guard isSubscription else {
                return "Signed in as \(who). Usage is billed to API credits."
            }
            guard let plan else { return "Signed in as \(who)." }
            return "Signed in as \(who) on Claude \(plan.capitalized)."
        case .signedOut:
            return "Claude Code is installed but not signed in."
        case .notInstalled:
            return "Claude Code isn't installed, or the app can't find it."
        }
    }

    /// What the user should do next, when there is something to do.
    var remedy: String? {
        switch self {
        case .signedIn:
            return nil
        case .signedOut:
            return "Run `claude auth login` in Terminal, then reopen this window."
        case .notInstalled:
            return "Install Claude Code, or set the path to the `claude` binary below."
        }
    }
}

/// Reports whether Claude Code is installed and signed in.
protocol ClaudeCodeStatusProviding: Sendable {
    func currentStatus() async -> ClaudeCodeStatus
}

/// Shells out to `claude auth status`, which prints the signed-in account as
/// JSON without spending any tokens.
struct ClaudeCodeStatusProvider: ClaudeCodeStatusProviding {
    private let locator: ClaudeCodeLocating

    init(locator: ClaudeCodeLocating = ClaudeCodeLocator()) {
        self.locator = locator
    }

    func currentStatus() async -> ClaudeCodeStatus {
        guard let executable = locator.locate() else { return .notInstalled }

        guard let data = await Self.run(executable, arguments: ["auth", "status"]),
              let payload = try? JSONDecoder().decode(AuthStatus.self, from: data)
        else { return .signedOut }

        guard payload.loggedIn else { return .signedOut }

        // `authMethod` is "claude.ai" for a Pro/Max login and something else
        // (or absent) when Claude Code is running on an API key instead.
        let isSubscription = payload.authMethod == "claude.ai"

        return .signedIn(
            account: payload.email,
            plan: payload.subscriptionType,
            isSubscription: isSubscription
        )
    }

    private struct AuthStatus: Decodable {
        let loggedIn: Bool
        let authMethod: String?
        let email: String?
        let subscriptionType: String?
    }

    /// Runs a short-lived command and returns stdout, or `nil` if it failed.
    private static func run(_ executable: URL, arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = ClaudeCodeWorkspace.directory

            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            // Read before waiting: a full pipe buffer would otherwise deadlock
            // the child against our wait.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
        }
    }
}

/// The working directory every `claude` invocation runs in.
///
/// A dedicated, empty directory keeps the companion out of whatever project the
/// user happens to be in: no `CLAUDE.md` discovery, no project memory, and a
/// stable home for the session transcripts that `--resume` reads back.
enum ClaudeCodeWorkspace {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base
            .appendingPathComponent(AppInfo.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
