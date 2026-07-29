import SwiftUI

/// A fenced code block: language chip, copy button, and horizontally
/// scrollable highlighted source.
struct CodeBlockView: View {
    let source: String
    let language: String?

    @State private var isHovering = false

    private var highlighted: AttributedString {
        SyntaxHighlighter.highlight(source, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(Theme.Fonts.code)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            Theme.Colors.codeBackground,
            in: RoundedRectangle(cornerRadius: Theme.Metrics.codeCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.codeCornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.separator)
        }
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Code block, \(SyntaxHighlighter.displayName(for: language))")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(SyntaxHighlighter.displayName(for: language))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Colors.subtleText)

            Spacer()

            CopyButton(text: source, label: "Copy")
                // Stays reachable by keyboard even when the pointer is elsewhere.
                .opacity(isHovering ? 1 : 0.35)
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 1)
    }
}

/// Three-dot "assistant is composing" indicator.
struct TypingIndicatorView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.subtleText)
                    .frame(width: 6, height: 6)
                    .scaleEffect(scale(for: index))
                    .opacity(0.4 + 0.6 * scale(for: index))
            }
        }
        .frame(height: 14)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityLabel("Claude is responding")
    }

    /// Staggers each dot by a third of the cycle.
    private func scale(for index: Int) -> CGFloat {
        let offset = Double(index) / 3.0
        let local = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.7 + 0.5 * CGFloat(sin(local * .pi))
    }
}
