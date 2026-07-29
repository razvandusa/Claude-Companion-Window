import SwiftUI
import AppKit

/// Multiline input that grows with its content.
///
/// Wraps `NSTextView` rather than using SwiftUI's `TextEditor` because the
/// composer needs three things SwiftUI doesn't expose: Return-sends /
/// Shift-Return-newlines, intercepting image pastes, and precise intrinsic
/// height for the grow-to-fit behaviour.
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Written back by the coordinator as the content grows.
    @Binding var height: CGFloat

    var minHeight: CGFloat = 20
    var maxHeight: CGFloat = 170
    var isEnabled: Bool = true

    /// Called when the user presses Return without Shift.
    var onSubmit: () -> Void
    /// Called when a paste carried images or files instead of plain text.
    var onPasteAttachments: (AttachmentLoader.Result) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.onPasteAttachments = { result in
            context.coordinator.parent.onPasteAttachments(result)
        }

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        // Preferred font rather than a fixed size, so the composer tracks the
        // user's text-size setting like the rest of the transcript.
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        // NSTextContainer pads every line fragment by 5pt, which would sit the
        // caret and the typed text to the right of the SwiftUI placeholder
        // drawn behind them.
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Message Claude")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none

        context.coordinator.textView = textView
        context.coordinator.observePanelPresentation()

        // Take focus as soon as the view is in a window.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.recalculateHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? ComposerTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight()
        }

        textView.isEditable = isEnabled
        textView.isSelectable = true
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var textView: ComposerTextView?
        private var presentationObserver: NSObjectProtocol?

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
        }

        /// Refocuses the composer every time the panel is shown.
        func observePanelPresentation() {
            guard presentationObserver == nil else { return }
            presentationObserver = NotificationCenter.default.addObserver(
                forName: PanelController.didPresentNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        func stopObserving() {
            if let presentationObserver {
                NotificationCenter.default.removeObserver(presentationObserver)
            }
            presentationObserver = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        /// Return sends; Shift-Return inserts a newline.
        func textView(
            _ textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            default:
                return false
            }
        }

        /// Measures laid-out text and reports the clamped height back to SwiftUI.
        func recalculateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer
            else { return }

            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let inset = textView.textContainerInset.height * 2
            let target = min(max(used + inset, parent.minHeight), parent.maxHeight)

            // Only scroll once the content has outgrown the cap.
            textView.enclosingScrollView?.hasVerticalScroller = used + inset > parent.maxHeight

            guard abs(parent.height - target) > 0.5 else { return }
            DispatchQueue.main.async { [parent] in
                parent.height = target
            }
        }
    }
}

/// `NSTextView` that routes image and file pastes to the attachment pipeline.
final class ComposerTextView: NSTextView {
    var onPasteAttachments: ((AttachmentLoader.Result) -> Void)?

    override func paste(_ sender: Any?) {
        // Plain text falls through to the default handler; anything else
        // (screenshots, copied files) becomes an attachment.
        if let result = AttachmentLoader.loadFromPasteboard(),
           !(result.attachments.isEmpty && result.rejected.isEmpty) {
            onPasteAttachments?(result)
            return
        }
        super.pasteAsPlainText(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘V is delivered as a key equivalent, so route it through `paste` to
        // pick up the attachment handling above.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
