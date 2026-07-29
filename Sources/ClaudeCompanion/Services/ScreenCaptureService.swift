import AppKit
import CoreGraphics
import OSLog

/// Screen captures that become attachments.
///
/// Everything here shells out to `/usr/sbin/screencapture` rather than using
/// ScreenCaptureKit: the CLI already owns the selection UI, the shutter sound
/// and — importantly — the screen-recording permission prompt, so the app never
/// has to reimplement any of it.
enum ScreenCaptureService {

    enum Mode {
        /// Crosshair selection; space bar switches to window picking.
        case selection
        /// Click a window to capture it.
        case window
        /// The display the panel is on, with no interaction.
        case fullScreen
    }

    /// The outcome of a capture. `cancelled` is separated from `failure` so
    /// pressing ESC in the crosshair never shows an error banner.
    enum Outcome {
        case captured(Attachment)
        case cancelled
        case failure(String)
    }

    private static let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "Capture")

    // MARK: - Interactive captures

    static func capture(_ mode: Mode) async -> Outcome {
        let destination = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: destination) }

        var arguments: [String]
        switch mode {
        case .selection: arguments = ["-i", "-x", "-o"]
        case .window: arguments = ["-i", "-w", "-x", "-o"]
        // -m keeps this to the main display; without it a multi-display setup
        // writes one file per screen and none of them is the path we asked for.
        case .fullScreen: arguments = ["-m", "-x", "-o"]
        }
        arguments.append(destination.path)

        return await run(arguments: arguments, destination: destination, name: defaultName(for: mode))
    }

    // MARK: - Window of a specific app

    /// Captures the frontmost window belonging to `app`.
    ///
    /// Used by "Work With": the picked app's window is what gets attached, so
    /// the model sees what the user is actually looking at.
    static func captureWindow(of app: CompanionApp) async -> Outcome {
        guard let pid = app.processIdentifier else {
            return .failure("\(app.name) isn't running.")
        }
        guard let windowID = frontmostWindowID(ownedBy: pid) else {
            return .failure("\(app.name) has no visible window to capture.")
        }

        let destination = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: destination) }

        return await run(
            arguments: ["-x", "-o", "-l\(windowID)", destination.path],
            destination: destination,
            name: "\(app.name).png"
        )
    }

    /// Largest on-screen, normal-layer window owned by the process.
    ///
    /// Layer 0 filters out panels, menus and the shadow windows apps keep
    /// around; largest-area then picks the document window over any inspector.
    static func frontmostWindowID(ownedBy pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let candidates = windows.filter { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (window[kCGWindowLayer as String] as? Int) == 0
        }

        let largest = candidates.max { lhs, rhs in
            windowArea(lhs) < windowArea(rhs)
        }

        return largest?[kCGWindowNumber as String] as? CGWindowID
    }

    private static func windowArea(_ window: [String: Any]) -> CGFloat {
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat
        else { return 0 }
        return width * height
    }

    // MARK: - Process

    private static func run(
        arguments: [String],
        destination: URL,
        name: String
    ) async -> Outcome {
        let status = await execute(arguments: arguments)

        // A non-zero exit is how `screencapture` reports ESC out of the
        // crosshair, which is a normal thing for a user to do.
        guard status == 0 else { return .cancelled }

        guard let data = try? Data(contentsOf: destination), !data.isEmpty else {
            return .cancelled
        }

        guard let attachment = AttachmentLoader.makeImageAttachment(from: data, filename: name) else {
            return .failure("The screenshot couldn't be read.")
        }

        return .captured(attachment)
    }

    private static func execute(arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                logger.error("screencapture failed to launch: \(error.localizedDescription, privacy: .public)")
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }

    // MARK: - Naming

    private static func defaultName(for mode: Mode) -> String {
        let stamp = Self.nameFormatter.string(from: Date())
        switch mode {
        case .selection, .fullScreen: return "Screenshot \(stamp).png"
        case .window: return "Window \(stamp).png"
        }
    }

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    private static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-capture-\(UUID().uuidString)")
            .appendingPathExtension("png")
    }
}
