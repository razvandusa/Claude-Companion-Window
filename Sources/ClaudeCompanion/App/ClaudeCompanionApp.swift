import SwiftUI

/// Entry point.
///
/// The app declares no `WindowGroup`: the only surface is the floating panel,
/// which `AppDelegate` owns. `Settings` is present so SwiftUI has a scene to
/// build, but the real settings UI is a sheet inside the panel.
@main
struct ClaudeCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
