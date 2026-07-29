import SwiftUI
import AppKit

/// One turn in the transcript.
///
/// User turns render as a right-aligned bubble; assistant turns render full
/// width without a bubble so long markdown stays readable.
struct MessageRowView: View {
    let message: Message
    let isStreaming: Bool

    @EnvironmentObject private var chat: ChatViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isHovering = false
    @State private var didCopy = false

    private var isLastTurn: Bool {
        chat.conversation.messages.last?.id == message.id
    }

    var body: some View {
        Group {
            switch message.role {
            case .user: userTurn
            case .assistant: assistantTurn
            }
        }
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.role == .user ? "You said" : "Claude said")
    }

    // MARK: - User

    private var userTurn: some View {
        HStack {
            Spacer(minLength: 40)

            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    AttachmentStrip(attachments: message.attachments, alignment: .trailing)
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(Theme.Fonts.body)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(
                            Theme.Colors.userBubble,
                            in: RoundedRectangle(
                                cornerRadius: Theme.Metrics.bubbleCornerRadius,
                                style: .continuous
                            )
                        )
                }
            }
        }
    }

    // MARK: - Assistant

    private var assistantTurn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.reasoning.isEmpty {
                ReasoningDisclosure(text: message.reasoning, isStreaming: isStreaming)
            }

            if !message.content.isEmpty {
                MarkdownContentView(markdown: message.content)
            }

            if isStreaming, !message.content.isEmpty {
                StreamingCaret()
            }

            if let errorDescription = message.errorDescription {
                ErrorNotice(description: errorDescription) {
                    chat.retryLastTurn()
                }
            }

            if message.stopReason == .maxTokens {
                Label("Response hit the output limit.", systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.orange)
            }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Copy, read aloud, mark unhelpful, retry.
    ///
    /// Always on screen rather than revealed on hover: these are the actions a
    /// reply is answered with, and hiding them behind the pointer costs a move
    /// and a guess every time.
    @ViewBuilder
    private var footer: some View {
        if !isStreaming, !message.content.isEmpty {
            HStack(spacing: 4) {
                MessageActionButton(systemImage: didCopy ? "checkmark" : "doc.on.doc", help: "Copy") {
                    Pasteboard.copy(message.plainText)
                    withAnimation(Theme.Animations.quick) { didCopy = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation(Theme.Animations.quick) { didCopy = false }
                    }
                }
                .accessibilityLabel(didCopy ? "Copied" : "Copy")

                ReadAloudButton(reader: environment.speech, message: message)

                MessageActionButton(
                    systemImage: message.feedback == .unhelpful
                        ? "hand.thumbsdown.fill"
                        : "hand.thumbsdown",
                    help: "Bad response"
                ) {
                    chat.toggleFeedback(.unhelpful, on: message.id)
                }
                .accessibilityLabel("Mark as a bad response")

                // Retry re-runs the last turn, so it is only offered on the
                // last turn — anywhere else the button would silently
                // regenerate a different message than the one it sits under.
                MessageActionButton(systemImage: "arrow.clockwise", help: "Try again") {
                    chat.retryLastTurn()
                }
                .disabled(chat.isStreaming || !isLastTurn)
                .accessibilityLabel("Regenerate this response")

                if let usage = message.usage, isHovering {
                    Text("\(usage.outputTokens) tokens")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.subtleText)
                        .padding(.leading, 4)
                        .transition(.opacity)
                }

                Spacer()
            }
            .animation(Theme.Animations.quick, value: isHovering)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy") {
            Pasteboard.copy(message.plainText)
        }

        ShareLink(item: message.plainText)

        if message.role == .assistant, !chat.isStreaming {
            Button("Retry") { chat.retryLastTurn() }
        }
    }
}

// MARK: - Supporting views

/// One icon in the action row under an assistant turn.
struct MessageActionButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(
                    isEnabled ? Theme.Colors.controlIcon : Theme.Colors.controlIcon.opacity(0.4)
                )
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Colors.hoverHighlight)
                        .opacity(isHovering && isEnabled ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .help(help)
    }
}

/// Speaker button that flips to a stop control while this turn is being read.
private struct ReadAloudButton: View {
    @ObservedObject var reader: SpeechReader
    let message: Message

    var body: some View {
        let isSpeaking = reader.isSpeaking(message.id)

        return MessageActionButton(
            systemImage: isSpeaking ? "stop.circle" : "speaker.wave.2",
            help: isSpeaking ? "Stop reading" : "Read aloud"
        ) {
            reader.toggle(message.content, messageID: message.id)
        }
        .accessibilityLabel(isSpeaking ? "Stop reading aloud" : "Read aloud")
    }
}

/// Collapsed by default; expands to show the model's summarized reasoning.
private struct ReasoningDisclosure: View {
    let text: String
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Theme.Animations.quick) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(isStreaming ? "Thinking…" : "Thought process")
                        .font(Theme.Fonts.caption)
                }
                .foregroundStyle(Theme.Colors.subtleText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide thought process" : "Show thought process")

            if isExpanded {
                Text(text)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.Colors.separator)
                            .frame(width: 2)
                    }
            }
        }
    }
}

/// Blinking block cursor shown at the tail of a streaming answer.
private struct StreamingCaret: View {
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.6))
            .frame(width: 7, height: 13)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
            .accessibilityHidden(true)
    }
}

/// Inline failure with a retry affordance.
private struct ErrorNotice: View {
    let description: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(description)
                .font(Theme.Fonts.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .buttonStyle(.link)
                .font(Theme.Fonts.caption)
        }
        .foregroundStyle(Theme.Colors.errorTint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Colors.errorTint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

/// Copy button that confirms with a checkmark.
struct CopyButton: View {
    let text: String
    var label: String?

    @State private var didCopy = false

    var body: some View {
        Button {
            Pasteboard.copy(text)
            withAnimation(Theme.Animations.quick) { didCopy = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation(Theme.Animations.quick) { didCopy = false }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                if let label {
                    Text(didCopy ? "Copied" : label)
                        .font(.system(size: 10))
                }
            }
            .frame(height: 20)
            .padding(.horizontal, label == nil ? 4 : 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(didCopy ? Color.green : Theme.Colors.subtleText)
        .help("Copy")
        .accessibilityLabel(didCopy ? "Copied" : "Copy")
    }
}

/// Thin wrapper so pasteboard writes live in one place.
enum Pasteboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
