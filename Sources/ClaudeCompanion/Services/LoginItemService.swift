import Foundation
import ServiceManagement
import OSLog

/// Registers the app as a login item using `SMAppService`.
///
/// Registration requires a bundled, signed app; when the app is run straight
/// from a build directory the call fails and the caller surfaces that rather
/// than silently leaving the toggle on.
enum LoginItemService {
    private static let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns `nil` on success, or a user-facing reason on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
            return "Couldn't update the login item: \(error.localizedDescription)"
        }
    }
}
