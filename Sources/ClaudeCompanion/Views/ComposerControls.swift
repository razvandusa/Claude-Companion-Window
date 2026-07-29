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
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: width * x, y: height * y)
        }

        var path = Path()

        // Left tip down to the bottom-right foot.
        path.move(to: point(0.38, 0.10))
        path.addLine(to: point(0.82, 0.86))

        // Right tip down to the bottom-left foot.
        path.move(to: point(0.62, 0.10))
        path.addLine(to: point(0.18, 0.86))

        // Crossbar, overhanging both diagonals.
        path.move(to: point(0.26, 0.62))
        path.addLine(to: point(0.74, 0.62))

        return path
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

    /// Split out so a `Menu` can borrow the same look for its label.
    var label: some View {
        icon()
            .foregroundStyle(foreground)
            .frame(width: Theme.Metrics.composerControl, height: Theme.Metrics.composerControl)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Colors.controlActive)
                    .opacity(isActive ? 1 : 0)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.Colors.hoverHighlight)
                            .opacity(isHovering && isEnabled ? 1 : 0)
                    }
            }
            .contentShape(Rectangle())
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
                .font(.system(size: isStreaming ? 11 : 14, weight: .bold))
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
