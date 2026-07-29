import AppKit

/// An application offered in the "Work With" picker.
///
/// Identity is the bundle identifier so a running instance and the installed
/// copy on disk collapse into one row.
struct CompanionApp: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var bundleURL: URL
    var isRunning: Bool
    /// Set only while the app is running; used to find its window to capture.
    var processIdentifier: pid_t?

    /// Subtitle shown after the name, matching the picker's "• Not running".
    var runningStateLabel: String? {
        isRunning ? nil : "Not running"
    }
}

/// Enumerates the apps the picker can offer: everything currently running,
/// plus what is installed in the usual application folders.
@MainActor
final class AppDirectory: ObservableObject {
    @Published private(set) var apps: [CompanionApp] = []

    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    /// Rebuilds the list. Cheap enough to run each time the picker opens, which
    /// is also what keeps the running/not-running state honest.
    func refresh() {
        var byIdentifier: [String: CompanionApp] = [:]

        // Running apps first, so their pid and running state win over the copy
        // found on disk.
        for application in workspace.runningApplications {
            guard application.activationPolicy == .regular,
                  let identifier = application.bundleIdentifier,
                  let url = application.bundleURL,
                  identifier != AppInfo.bundleIdentifier
            else { continue }

            byIdentifier[identifier] = CompanionApp(
                id: identifier,
                name: application.localizedName ?? url.deletingPathExtension().lastPathComponent,
                bundleURL: url,
                isRunning: true,
                processIdentifier: application.processIdentifier
            )
        }

        for url in installedApplicationURLs() {
            guard let bundle = Bundle(url: url),
                  let identifier = bundle.bundleIdentifier,
                  identifier != AppInfo.bundleIdentifier,
                  byIdentifier[identifier] == nil
            else { continue }

            byIdentifier[identifier] = CompanionApp(
                id: identifier,
                name: fileManager.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: ""),
                bundleURL: url,
                isRunning: false,
                processIdentifier: nil
            )
        }

        apps = byIdentifier.values.sorted(by: Self.pickerOrder)
    }

    /// Running apps float to the top, then everything alphabetically.
    nonisolated static func pickerOrder(_ lhs: CompanionApp, _ rhs: CompanionApp) -> Bool {
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// Case- and diacritic-insensitive substring match on the app name.
    nonisolated static func filter(_ apps: [CompanionApp], query: String) -> [CompanionApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    func icon(for app: CompanionApp) -> NSImage {
        workspace.icon(forFile: app.bundleURL.path)
    }

    private func installedApplicationURLs() -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        return roots.flatMap { root -> [URL] in
            let contents = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return (contents ?? []).filter { $0.pathExtension == "app" }
        }
    }
}
