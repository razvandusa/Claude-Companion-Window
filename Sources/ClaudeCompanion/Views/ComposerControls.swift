import SwiftUI

/// The App Store "A" used for the "Work With" picker.
///
/// Drawn rather than taken from SF Symbols: nothing in the symbol set reads as
/// "applications" at this size without looking like a grid of tiles.
///
/// The mark is not a letter A. It is three rounded strokes: two diagonals that
/// *cross* a little below the top — leaving the two small tips that give the
/// logo its character — and a crossbar that runs past both of them.
struct AppsGlyph: Shape {
    /// Lean of each diagonal away from vertical. This alone sets how squat the
    /// mark is, and with it how far the equal-length crossbar overhangs the
    /// feet: level with them at ~35°, a clear 1pt past them at 30°.
    private let lean = Angle(degrees: 30)
    /// Fraction of a diagonal's horizontal run that sits above the crossing,
    /// i.e. how far the two tips poke out of the top.
    private let tipFraction: CGFloat = 0.13
    /// How far down the diagonals' vertical extent the crossbar sits.
    ///
    /// Low enough that the splay it cuts off at the bottom answers the apex at
    /// the top; nearer the middle the mark goes top-heavy and starts reading
    /// as a letter A again.
    private let crossbarFraction: CGFloat = 0.81
    /// Stroke length as a fraction of the frame, leaving room for round caps.
    ///
    /// Everything is laid out around the frame's centre, so this draws all
    /// three strokes in or out together without disturbing their equality.
    private let scale: CGFloat = 0.80

    func path(in rect: CGRect) -> Path {
        // One length, used for all three strokes. Because a diagonal's run and
        // drop are that length's sine and cosine, each diagonal comes out
        // exactly as long as the crossbar by construction rather than by
        // hand-tuned endpoints.
        let length = min(rect.width, rect.height) * scale
        let run = length * sin(lean.radians)
        let drop = length * cos(lean.radians)

        let midX = rect.midX
        let top = rect.midY - drop / 2
        let bottom = rect.midY + drop / 2
        let halfTip = run * tipFraction

        var path = Path()

        // Upper-left tip down to the lower-right foot, and its mirror.
        path.move(to: CGPoint(x: midX - halfTip, y: top))
        path.addLine(to: CGPoint(x: midX - halfTip + run, y: bottom))

        path.move(to: CGPoint(x: midX + halfTip, y: top))
        path.addLine(to: CGPoint(x: midX + halfTip - run, y: bottom))

        // Crossbar.
        let crossbarY = top + drop * crossbarFraction
        path.move(to: CGPoint(x: midX - length / 2, y: crossbarY))
        path.addLine(to: CGPoint(x: midX + length / 2, y: crossbarY))

        return path
    }
}

/// The hit target, highlight and hover wash shared by every control on the
/// composer's row — including the `+`, which is a `Menu` rather than a button
/// and so can't get them from ``ComposerIconButton``.
struct ComposerIconChrome<Content: View>: View {
    var isActive: Bool = false
    var isHovering: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: Theme.Metrics.composerControl, height: Theme.Metrics.composerControl)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Colors.controlActive)
                    .opacity(isActive ? 1 : 0)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.Colors.hoverHighlight)
                            .opacity(isHovering ? 1 : 0)
                    }
            }
            .contentShape(Rectangle())
    }
}

/// One icon button on the composer's control row.
///
/// Icons are supplied either as an SF Symbol or as a shape, so the drawn apps
/// glyph sits on exactly the same hit target and highlight as the rest.
struct ComposerIconButton<Icon: View>: View {
    var isActive: Bool = false
    var tint: Color?
    let help: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .help(help)
    }

    private var label: some View {
        ComposerIconChrome(isActive: isActive, isHovering: isHovering && isEnabled) {
            icon().foregroundStyle(foreground)
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.Colors.controlIcon.opacity(0.4) }
        return tint ?? Theme.Colors.controlIcon
    }
}

/// An SF Symbol at the control row's icon size.
struct ComposerSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(Theme.Fonts.controlIcon)
    }
}

extension ComposerIconButton where Icon == ComposerSymbol {
    /// Convenience for the SF Symbol buttons: globe, mic.
    init(
        systemImage: String,
        isActive: Bool = false,
        tint: Color? = nil,
        help: String,
        action: @escaping () -> Void
    ) {
        self.init(isActive: isActive, tint: tint, help: help, action: action) {
            ComposerSymbol(name: systemImage)
        }
    }
}

/// Round send / stop button at the trailing end of the control row.
struct SendButton: View {
    let isStreaming: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: isStreaming ? 11 : 15, weight: .semibold))
                .foregroundStyle(isActive ? Theme.Colors.sendGlyph : Theme.Colors.sendGlyphDisabled)
                .frame(width: Theme.Metrics.sendButton, height: Theme.Metrics.sendButton)
                .background {
                    Circle().fill(isActive ? Theme.Colors.sendFill : Theme.Colors.sendFillDisabled)
                }
                .scaleEffect(isHovering && isActive ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .help(isStreaming ? "Stop generating" : "Send (Return)")
        .accessibilityLabel(isStreaming ? "Stop generating" : "Send message")
    }

    /// Streaming counts as active: the stop button is always pressable.
    private var isActive: Bool { isStreaming || isEnabled }
}
