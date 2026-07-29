import SwiftUI

/// The App Store-style "A" used for the "Work With" picker.
///
/// Drawn rather than taken from SF Symbols: nothing in the symbol set reads as
/// "applications" at this size without looking like a grid of tiles.
struct AppsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        // The peak and its two legs.
        path.move(to: CGPoint(x: width * 0.18, y: height * 0.84))
        path.addLine(to: CGPoint(x: width * 0.51, y: height * 0.16))
        path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.84))

        // Crossbar, running past the left leg the way the real mark does.
        path.move(to: CGPoint(x: width * 0.30, y: height * 0.60))
        path.addLine(to: CGPoint(x: width * 0.72, y: height * 0.60))

        // Short stroke echoing the right leg on the left shoulder.
        path.move(to: CGPoint(x: width * 0.38, y: height * 0.29))
        path.addLine(to: CGPoint(x: width * 0.22, y: height * 0.62))

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
