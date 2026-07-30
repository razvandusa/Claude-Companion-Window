import AppKit

/// The floating chat window.
///
/// An `NSPanel` (rather than `NSWindow`) so it can float above other apps and
/// join every Space without stealing the active app's window ordering. The
/// panel is created once and hidden on dismiss — never destroyed — so reopening
/// is instant and in-flight streams survive.
final class CompanionPanel: NSPanel {

    /// Corner radius of the content, matched by the window shadow.
    static let cornerRadius: CGFloat = 16

    /// Smallest usable size; the composer stops being usable below this.
    static let minimumSize = NSSize(width: 380, height: 340)

    /// Size used the first time the panel is shown.
    static let defaultSize = NSSize(width: 440, height: 640)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Show above full-screen apps and follow the user across Spaces.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // The SwiftUI content draws the rounded, translucent surface; the window
        // itself is transparent so the shadow hugs that shape.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        isMovableByWindowBackground = true
        // Hiding rather than closing is what makes reopening instant.
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        minSize = Self.minimumSize
        contentMinSize = Self.minimumSize
    }

    /// Required so the panel can take keyboard focus for the composer.
    override var canBecomeKey: Bool { true }

    /// A panel should never become the main window — that belongs to the app
    /// the user was actually working in.
    override var canBecomeMain: Bool { false }
}
