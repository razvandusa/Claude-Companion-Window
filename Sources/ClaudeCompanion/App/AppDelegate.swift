import AppKit
import SwiftUI
import KeyboardShortcuts

/// Wires up the accessory-app lifecycle: the global hotkey, the menu bar item
/// and the floating panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private var panelController: PanelController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no menu bar: this is a companion window, not an app
        // the user switches to.
        NSApp.setActivationPolicy(.accessory)

        panelController = PanelController(environment: environment)
        environment.panelController = panelController

        registerGlobalShortcut()
        installStatusItem()

        // The system is the source of truth for the login item — a registration
        // that failed, or one the user removed in System Settings, would
        // otherwise leave the toggle showing a stale value.
        environment.settings.launchAtLogin = LoginItemService.isEnabled

        // First run leads with the window open, and with Settings on top when
        // Claude Code is missing or signed out — that's the only setup step.
        let isFirstRun = !environment.settings.hasCompletedOnboarding
        environment.settings.hasCompletedOnboarding = true
        if isFirstRun { panelController.show() }

        Task {
            await environment.chat.restore()
            if isFirstRun, !environment.chat.status.canSend {
                environment.isShowingSettings = true
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The panel is hidden, not closed — the app keeps running for the hotkey.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.chat.cancelStreaming()
    }

    // MARK: - Global shortcut

    private func registerGlobalShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleCompanion) { [weak self] in
            self?.panelController.toggle()
        }
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "bubble.left.and.text.bubble.right",
            accessibilityDescription: AppInfo.name
        )
        item.button?.toolTip = AppInfo.name

        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show \(AppInfo.name)",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleCompanion) {
            toggle.setShortcut(shortcut)
        }
        menu.addItem(toggle)

        let newChat = NSMenuItem(title: "New Chat", action: #selector(newChat), keyEquivalent: "n")
        newChat.target = self
        menu.addItem(newChat)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }

    @objc private func newChat() {
        environment.chat.startNewConversation()
        panelController.show()
    }

    @objc private func openSettings() {
        panelController.show()
        environment.isShowingSettings = true
    }
}
