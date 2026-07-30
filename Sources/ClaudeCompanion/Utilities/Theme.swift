import SwiftUI
import AppKit

/// Shared visual constants.
///
/// The palette is modelled on a dark companion window, but every colour is
/// declared as a light/dark pair so the panel still reads correctly when the
/// user is in light mode.
enum Theme {
    enum Metrics {
        static let panelCornerRadius: CGFloat = CompanionPanel.cornerRadius
        /// User bubbles are pill-shaped; this is half the single-line height.
        static let bubbleCornerRadius: CGFloat = 19
        static let codeCornerRadius: CGFloat = 10
        /// The composer's outer container.
        static let composerCornerRadius: CGFloat = 18
        static let horizontalPadding: CGFloat = 16
        static let messageSpacing: CGFloat = 20
        static let headerHeight: CGFloat = 46
        /// Square hit target for the icon buttons on the composer's control row.
        static let composerControl: CGFloat = 30
        static let sendButton: CGFloat = 34
    }

    enum Colors {
        /// Tint over the window material.
        ///
        /// Deliberately thin: the `NSVisualEffectView` under it is doing the
        /// work, and anything heavier turns a floating companion into an
        /// opaque window sitting on the desktop.
        static let surface = dynamic(
            light: NSColor(white: 0.97, alpha: 0.55),
            dark: NSColor(white: 0.08, alpha: 0.42)
        )

        /// Fill behind a user message bubble.
        static let userBubble = dynamic(
            light: NSColor(white: 0, alpha: 0.07),
            dark: NSColor(white: 1, alpha: 0.13)
        )

        /// Fill of the composer container.
        static let composerFill = dynamic(
            light: NSColor(white: 1, alpha: 0.70),
            dark: NSColor(white: 1, alpha: 0.055)
        )

        static let composerStroke = dynamic(
            light: NSColor(white: 0, alpha: 0.12),
            dark: NSColor(white: 1, alpha: 0.11)
        )

        /// Resting colour of the icon buttons around the composer and header.
        static let controlIcon = dynamic(
            light: NSColor(white: 0.35, alpha: 1),
            dark: NSColor(white: 0.68, alpha: 1)
        )

        /// Background of an icon button that is toggled on or showing a popover.
        static let controlActive = dynamic(
            light: NSColor(white: 0, alpha: 0.09),
            dark: NSColor(white: 1, alpha: 0.13)
        )

        /// Extra wash layered over a control while the pointer is over it.
        static let hoverHighlight = dynamic(
            light: NSColor(white: 0, alpha: 0.07),
            dark: NSColor(white: 1, alpha: 0.08)
        )

        /// Send button once there is something to send.
        static let sendFill = dynamic(
            light: NSColor(white: 0.12, alpha: 1),
            dark: NSColor(white: 0.93, alpha: 1)
        )

        static let sendGlyph = dynamic(
            light: NSColor(white: 1, alpha: 1),
            dark: NSColor(white: 0.06, alpha: 1)
        )

        static let sendFillDisabled = dynamic(
            light: NSColor(white: 0, alpha: 0.10),
            dark: NSColor(white: 1, alpha: 0.16)
        )

        static let sendGlyphDisabled = dynamic(
            light: NSColor(white: 0, alpha: 0.35),
            dark: NSColor(white: 1, alpha: 0.45)
        )

        /// Popover surface for the app picker.
        static let popoverFill = dynamic(
            light: NSColor(white: 0.98, alpha: 1),
            dark: NSColor(white: 0.14, alpha: 1)
        )

        static let assistantBubble = Color.primary.opacity(0.055)
        static let codeBackground = Color.primary.opacity(0.07)
        static let separator = Color.primary.opacity(0.10)
        static let subtleText = Color.secondary
        static let errorTint = Color.red

        /// Builds an appearance-aware colour so light mode isn't an afterthought.
        private static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }
    }

    enum Animations {
        /// Used when a new message arrives.
        static let messageArrival = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Used for hover and small state flips.
        static let quick = Animation.easeOut(duration: 0.14)
        /// Used while streaming text grows.
        static let streaming = Animation.easeOut(duration: 0.12)
    }

    /// Semantic text styles rather than fixed point sizes, so everything
    /// tracks the user's Dynamic Type setting.
    enum Fonts {
        static let body = Font.body
        static let code = Font.system(.callout, design: .monospaced)
        static let caption = Font.caption
        static let title = Font.system(.body, design: .default).weight(.semibold)
        /// Icons on the composer control row.
        ///
        /// Medium, not light: these are solid line glyphs that have to hold
        /// their own against the filled send button at the other end of the
        /// row, and thin strokes wash out against the composer fill.
        static let controlIcon = Font.system(size: 19, weight: .medium)

        /// The `+`, at a larger point size than the icons beside it.
        ///
        /// SF Symbols draws `plus` small inside its em box, so matching the
        /// others' point size leaves it visibly the runt of the row; matching
        /// their *drawn* size is what's wanted.
        static let plusIcon = Font.system(size: 21, weight: .regular)
    }
}
