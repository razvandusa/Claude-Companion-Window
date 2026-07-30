import AppKit
import SwiftUI
import Combine

/// Owns the lifecycle of the floating panel: showing, hiding, remembering where
/// it was, and the keyboard handling that only applies while it is on screen.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    /// Posted when the panel becomes visible, so the composer can take focus.
    ///
    /// `nonisolated` so views can observe it without hopping actors.
    nonisolated static let didPresentNotification =
        Notification.Name("PanelControllerDidPresent")

    private let environment: AppEnvironment
    private var panel: CompanionPanel?
    private var keyMonitor: Any?
    private var frameSaveTask: Task<Void, Never>?

    /// Suppresses click-outside dismissal while a sheet or menu owns the focus.
    private var modalDepth = 0

    /// Mirrors ``AppEnvironment/isExpanded``; the window follows it.
    private var isExpanded = false
    /// Height to restore when the panel expands again.
    private var expandedHeight = CompanionPanel.defaultSize.height
    /// A resize requested while a sheet was open, applied when it closes.
    private var deferredExpansion: Bool?
    /// The panel's frame before a sheet resized it, restored when it closes.
    private var frameBeforeSheet: NSRect?
    /// When the panel was last put away, for the idle reset.
    private var hiddenAt: Date?
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()

        environment.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.setExpanded(expanded, animated: true)
            }
            .store(in: &cancellables)

        // While collapsed the window is exactly as tall as the composer, so a
        // draft that wraps onto a second line grows the bar with it.
        environment.$collapsedContentHeight
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, !self.isExpanded else { return }
                self.setExpanded(false, animated: false)
            }
            .store(in: &cancellables)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Presentation

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        resetIfIdleTooLong()

        let panel = existingOrNewPanel()

        if !panel.isVisible {
            positionForPresentation(panel)
            panel.alphaValue = 0
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installKeyMonitor()
        NotificationCenter.default.post(name: Self.didPresentNotification, object: nil)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        saveFrame(panel, immediately: true)
        removeKeyMonitor()
        hiddenAt = Date()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            // orderOut, never close: the panel and its SwiftUI state are reused.
            panel?.orderOut(nil)
        }
    }

    /// Call around sheets and menus so a transient focus loss doesn't dismiss
    /// the whole panel.
    func beginModalPresentation() { modalDepth += 1 }

    /// Sizes the panel to exactly contain a sheet of `size`.
    ///
    /// Not `max(current, sheet)`: any window bigger than its sheet shows a band
    /// of panel around it, and AppKit insets a sheet below the titlebar even on
    /// a `fullSizeContentView` window — so the height has to be the sheet plus
    /// that inset, and nothing more. Call before presenting, not after.
    func makeRoomForSheet(_ size: CGSize) {
        guard let panel else { return }

        if frameBeforeSheet == nil {
            frameBeforeSheet = panel.frame
        }

        // The part of the frame a sheet is pushed below.
        let titlebarInset = panel.frame.height - panel.contentLayoutRect.height
        let target = NSSize(width: size.width, height: size.height + titlebarInset)

        var fitted = NSRect(
            x: panel.frame.midX - target.width / 2,
            y: panel.frame.minY,
            width: target.width,
            height: target.height
        )

        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            if fitted.maxY > visible.maxY { fitted.origin.y = visible.maxY - target.height }
            if fitted.maxX > visible.maxX { fitted.origin.x = visible.maxX - target.width }
            if fitted.minX < visible.minX { fitted.origin.x = visible.minX }
        }

        // Room has to exist before the sheet animates in, so this one isn't
        // deferred the way an ordinary expansion would be.
        panel.minSize = target
        panel.contentMinSize = target
        panel.setFrame(fitted, display: true)
        panel.invalidateShadow()
    }

    /// Puts the panel back where it was before a sheet resized it.
    private func restoreFrameFromSheet() {
        guard let panel, let saved = frameBeforeSheet else { return }
        frameBeforeSheet = nil

        panel.minSize = CompanionPanel.minimumSize
        panel.contentMinSize = CompanionPanel.minimumSize
        panel.setFrame(saved, display: true)
    }

    func endModalPresentation() {
        modalDepth = max(0, modalDepth - 1)
        guard modalDepth == 0 else { return }

        // Restore the panel's own size unconditionally: a resize may have been
        // held back while the sheet was up, and the sheet may also have grown
        // the window past where it should sit.
        let deferred = deferredExpansion ?? isExpanded
        deferredExpansion = nil

        Task { [weak self] in
            // Let the sheet finish dismissing first — resizing the window out
            // from under the tail of that animation is what makes it lurch.
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self else { return }
            guard self.modalDepth == 0 else {
                // Something else opened in the meantime; wait for that too.
                self.deferredExpansion = deferred
                return
            }
            // Undo the sheet's sizing first — it replaced both dimensions, and
            // `setExpanded` only ever adjusts the height.
            self.restoreFrameFromSheet()
            self.setExpanded(deferred, animated: true)
        }
    }

    /// Takes the panel off screen for the duration of `work`, then brings it
    /// back where it was.
    ///
    /// Screen capture is the reason this exists: a floating companion window
    /// would otherwise be sitting in the middle of every screenshot the user
    /// takes from it.
    func performWithPanelHidden<T>(_ work: () async -> T) async -> T {
        beginModalPresentation()
        defer { endModalPresentation() }

        let wasVisible = isVisible
        if wasVisible {
            panel?.orderOut(nil)
        }

        let result = await work()

        if wasVisible {
            panel?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: Self.didPresentNotification, object: nil)
        }

        return result
    }

    /// Starts fresh when the panel has been closed for a long time.
    ///
    /// Reopening hours later to yesterday's half-finished conversation is
    /// almost never what was wanted; reopening to an empty bar is. Anything
    /// closed and reopened within the window is left exactly as it was.
    ///
    /// The old conversation is not lost — it has already been persisted, and
    /// it stays in the history menu.
    private func resetIfIdleTooLong() {
        guard let hiddenAt else { return }
        guard Date().timeIntervalSince(hiddenAt) >= AppEnvironment.idleResetInterval else {
            return
        }

        self.hiddenAt = nil
        guard environment.chat.hasMessages else { return }
        environment.chat.startNewConversation()
    }

    // MARK: - Expansion

    /// Grows the window upward from its bottom edge, or shrinks it back.
    ///
    /// The bottom edge is what stays put: the composer is where the user is
    /// looking and typing, so it must not jump when a reply arrives and the
    /// transcript appears above it.
    private func setExpanded(_ expanded: Bool, animated: Bool) {
        // A sheet is laid out against the panel it belongs to. Shrinking the
        // window under an open Settings sheet — which is what deleting every
        // conversation does, by emptying the transcript — leaves the sheet
        // hanging off a window that is suddenly composer-sized.
        guard modalDepth == 0 else {
            deferredExpansion = expanded
            return
        }

        let wasExpanded = isExpanded
        isExpanded = expanded

        guard let panel else { return }

        if wasExpanded, !expanded {
            expandedHeight = panel.frame.height
        }

        let targetHeight = expanded
            ? max(expandedHeight, CompanionPanel.minimumSize.height)
            : environment.collapsedContentHeight

        let minimum = expanded ? CompanionPanel.minimumSize : collapsedMinimumSize
        panel.minSize = minimum
        panel.contentMinSize = minimum
        // A bar sized to its content has nothing to resize vertically.
        if expanded {
            panel.styleMask.insert(.resizable)
        } else {
            panel.styleMask.remove(.resizable)
        }

        let frame = panel.frame
        guard abs(frame.height - targetHeight) > 0.5 else { return }

        // origin.y is the bottom edge in AppKit coordinates, so holding it
        // fixed is what pins the composer and grows the window upward.
        var target = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: targetHeight
        )

        // Growing upward can run off the top of the display.
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame,
           target.maxY > visible.maxY {
            target.origin.y = visible.maxY - targetHeight
        }

        panel.setFrame(target, display: true, animate: animated)
        panel.invalidateShadow()
    }

    private var collapsedMinimumSize: NSSize {
        NSSize(
            width: CompanionPanel.minimumSize.width,
            height: environment.collapsedContentHeight
        )
    }

    // MARK: - Panel construction

    private func existingOrNewPanel() -> CompanionPanel {
        if let panel { return panel }

        let panel = CompanionPanel()
        panel.delegate = self

        let root = RootView()
            .environmentObject(environment)
            .environmentObject(environment.settings)
            .environmentObject(environment.chat)

        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        panel.contentView = hosting

        restoreFrame(into: panel)
        self.panel = panel
        return panel
    }

    // MARK: - Frame persistence

    private func restoreFrame(into panel: CompanionPanel) {
        guard let description = environment.settings.panelFrameDescription else {
            centerOnActiveScreen(panel)
            return
        }

        let saved = NSRectFromString(description)
        guard saved.width >= CompanionPanel.minimumSize.width,
              saved.height >= CompanionPanel.minimumSize.height,
              isOnAVisibleScreen(saved)
        else {
            centerOnActiveScreen(panel)
            return
        }

        panel.setFrame(saved, display: false)
    }

    /// Guards against restoring onto a display that has since been unplugged.
    private func isOnAVisibleScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private func centerOnActiveScreen(_ panel: CompanionPanel) {
        let screen = screenUnderCursor() ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }

        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            // Sits a little above centre, the way a launcher-style window should.
            y: visible.midY - size.height / 2 + visible.height * 0.08
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    /// Moves the panel onto the display the user is currently looking at, but
    /// keeps the remembered size.
    private func positionForPresentation(_ panel: CompanionPanel) {
        guard let screen = screenUnderCursor() else { return }
        guard !screen.visibleFrame.intersects(panel.frame) else { return }
        centerOnActiveScreen(panel)
    }

    private func screenUnderCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    /// Coalesces the writes that live resizing and dragging would otherwise
    /// produce on every frame.
    private func saveFrame(_ panel: NSWindow, immediately: Bool = false) {
        frameSaveTask?.cancel()

        let description = NSStringFromRect(panel.frame)

        if immediately {
            environment.settings.panelFrameDescription = description
            return
        }

        frameSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.environment.settings.panelFrameDescription = description
        }
    }

    // MARK: - Keyboard

    /// ESC and ⌘W dismiss the panel. There is no menu bar to own ⌘W in an
    /// accessory app, so a local monitor is the only place to catch it.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            let isEscape = event.keyCode == 53
            let isCommandW = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "w"

            guard isEscape || isCommandW else { return event }

            // ESC first cancels a running response; a second press dismisses.
            if isEscape, self.environment.chat.isStreaming {
                self.environment.chat.cancelStreaming()
                return nil
            }

            self.hide()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    // MARK: - NSWindowDelegate

    /// Hide instead of destroying, so state and in-flight streams survive.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard environment.settings.dismissOnClickOutside, modalDepth == 0 else { return }
        // Deferred so a click that opens one of our own menus doesn't dismiss
        // the panel out from under it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, !panel.isKeyWindow, self.modalDepth == 0 else { return }
            self.hide()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        saveFrame(panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        panel.invalidateShadow()
        saveFrame(panel)
    }
}
