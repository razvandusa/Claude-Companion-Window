import Foundation

/// Finds the `claude` executable on disk.
///
/// A bundled `.app` is launched by `launchd`, not by a shell, so it inherits a
/// bare `PATH` that contains none of the places Claude Code actually installs
/// to. Probing the known locations directly is both faster and more reliable
/// than shelling out; the login-shell lookup is only a last resort for unusual
/// installs (nvm, asdf, a custom prefix).
protocol ClaudeCodeLocating: Sendable {
    /// Absolute path to an executable `claude`, or `nil` if none was found.
    func locate() -> URL?
}

/// `@unchecked` because `UserDefaults` and `FileManager` are documented as
/// thread-safe but aren't yet annotated `Sendable`.
struct ClaudeCodeLocator: ClaudeCodeLocating, @unchecked Sendable {
    /// `UserDefaults` key holding an explicit path set in Settings.
    static let overrideDefaultsKey = "settings.claudeExecutablePath"

    /// Checked in order. Covers the native installer, both Homebrew prefixes,
    /// npm globals, and Bun.
    static let searchPaths: [String] = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude",
        "~/.bun/bin/claude",
        "~/.npm-global/bin/claude",
        "/opt/homebrew/opt/node/bin/claude"
    ]

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func locate() -> URL? {
        if let override = overridePath() { return override }

        for candidate in Self.searchPaths {
            let url = URL(fileURLWithPath: (candidate as NSString).expandingTildeInPath)
            if isExecutable(url) { return url }
        }

        return locateViaLoginShell()
    }

    /// An explicit path from Settings wins, so an unusual install can always be
    /// pointed at by hand. Read fresh each time rather than cached, so a change
    /// takes effect without relaunching.
    private func overridePath() -> URL? {
        guard let raw = defaults.string(forKey: Self.overrideDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }

        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        return isExecutable(url) ? url : nil
    }

    private func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    /// Asks a login shell where `claude` lives. This picks up version managers
    /// that only put themselves on `PATH` from a shell profile.
    private func locateViaLoginShell() -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v claude"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else { return nil }

        let url = URL(fileURLWithPath: path)
        return isExecutable(url) ? url : nil
    }
}
