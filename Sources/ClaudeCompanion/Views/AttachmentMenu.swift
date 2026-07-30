import AppKit
import SwiftUI

/// The composer's `+` menu, built as a real `NSMenu`.
///
/// SwiftUI's `Menu` renders its label through AppKit, which imposes its own
/// font and control size and swallows hover — so the `+` could not be sized or
/// highlighted to match the buttons beside it. Popping the menu by hand keeps
/// the label an ordinary SwiftUI button, and the menu itself is still the
/// system's, submenu behaviour and all.
enum AttachmentMenu {

    @MainActor
    static func menu(for chat: ChatViewModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ClosureMenuItem(title: "Upload file") {
            chat.presentOpenPanel(imagesOnly: false)
        })
        menu.addItem(ClosureMenuItem(title: "Upload photo") {
            chat.presentOpenPanel(imagesOnly: true)
        })

        let screenshot = NSMenuItem(title: "Take screenshot", action: nil, keyEquivalent: "")
        let screenshotMenu = NSMenu()
        screenshotMenu.autoenablesItems = false
        screenshotMenu.addItem(ClosureMenuItem(title: "Selection…") {
            chat.attachScreenshot(.selection)
        })
        screenshotMenu.addItem(ClosureMenuItem(title: "Window…") {
            chat.attachScreenshot(.window)
        })
        screenshotMenu.addItem(ClosureMenuItem(title: "Entire Screen") {
            chat.attachScreenshot(.fullScreen)
        })
        screenshot.submenu = screenshotMenu
        menu.addItem(screenshot)

        menu.addItem(ClosureMenuItem(title: "Take photo") {
            chat.attachCameraPhoto()
        })

        return menu
    }

    /// Shows the menu above `view`, the way a composer pinned to the bottom of
    /// the panel needs it. AppKit flips it back down if there is no room.
    @MainActor
    static func present(_ menu: NSMenu, from view: NSView) {
        let origin = NSPoint(x: 0, y: view.bounds.maxY + 6)
        menu.popUp(positioning: nil, at: origin, in: view)
    }
}

/// Menu item that runs a closure, so the menu can be built inline instead of
/// through a target-action object that has to be kept alive alongside it.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        // `target` is weak, but the menu owns this item for as long as it is
        // on screen, so pointing it at self is safe.
        target = self
        isEnabled = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        handler()
    }
}

/// Captures the backing `NSView` of whatever it is placed behind, so an
/// `NSMenu` can be anchored to a SwiftUI button.
struct MenuAnchor: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        DispatchQueue.main.async { view = anchor }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
