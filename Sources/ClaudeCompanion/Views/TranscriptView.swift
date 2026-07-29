import SwiftUI

/// Scrollable conversation with sticky-bottom auto-scroll.
struct TranscriptView: View {
    @EnvironmentObject private var chat: ChatViewModel

    private let bottomAnchor = "transcript.bottom"

    /// Tracks whether the view is scrolled to the end. Auto-scroll only follows
    /// new content while the user is already at the bottom — otherwise reading
    /// back through a long answer would be yanked away mid-sentence.
    @State private var isPinnedToBottom = true
    @State private var containerHeight: CGFloat = 0
    @State private var bottomOffset: CGFloat = 0

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Metrics.messageSpacing) {
                        if chat.conversation.messages.isEmpty {
                            EmptyStateView()
                                .padding(.top, 28)
                        }

                        ForEach(chat.conversation.messages) { message in
                            MessageRowView(
                                message: message,
                                isStreaming: chat.streamingMessageID == message.id
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            ))
                        }

                        if chat.isAwaitingFirstToken {
                            TypingIndicatorView()
                                .padding(.leading, 2)
                                .transition(.opacity)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                            .background {
                                GeometryReader { proxyGeometry in
                                    Color.clear.preference(
                                        key: BottomOffsetKey.self,
                                        value: proxyGeometry.frame(in: .named("transcript")).minY
                                    )
                                }
                            }
                    }
                    .padding(.horizontal, Theme.Metrics.horizontalPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Inside the content on purpose — see the type's note.
                    .background { OverlayScrollerConfigurator() }
                }
                .coordinateSpace(name: "transcript")
                .onPreferenceChange(BottomOffsetKey.self) { value in
                    bottomOffset = value
                    isPinnedToBottom = (value - containerHeight) < 60
                }
                .onChange(of: chat.conversation.messages.count) { _, _ in
                    scroll(proxy, animated: true, force: true)
                }
                .onChange(of: chat.conversation.messages.last?.content) { _, _ in
                    guard isPinnedToBottom else { return }
                    scroll(proxy, animated: false, force: false)
                }
                .onChange(of: chat.isAwaitingFirstToken) { _, _ in
                    guard isPinnedToBottom else { return }
                    scroll(proxy, animated: true, force: false)
                }
                .onAppear {
                    containerHeight = outer.size.height
                    scroll(proxy, animated: false, force: true)
                }
                .onChange(of: outer.size.height) { _, newValue in
                    containerHeight = newValue
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isPinnedToBottom, chat.hasMessages {
                        ScrollToBottomButton {
                            withAnimation(Theme.Animations.messageArrival) {
                                proxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                            isPinnedToBottom = true
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, 10)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(Theme.Animations.messageArrival, value: chat.conversation.messages.count)
                .animation(Theme.Animations.quick, value: isPinnedToBottom)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool, force: Bool) {
        guard force || isPinnedToBottom else { return }
        // Deferred a runloop turn so the newly inserted row is laid out first.
        DispatchQueue.main.async {
            if animated {
                withAnimation(Theme.Animations.streaming) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }
}

/// Strips the slot from the transcript's scrollbar.
///
/// With "Show scroll bars: Always" set in System Settings, AppKit gives the
/// scroll view a *legacy* scroller: a knob riding in a drawn slot. Over a
/// translucent panel that slot reads as a grey box glued to the right edge.
///
/// Asking for the overlay style is not enough on its own — AppKit restores the
/// legacy style from the system preference — so the scroller is also replaced
/// with one that declines to draw its slot. The knob, and all of its normal
/// drag behaviour, are untouched.
///
/// Must be mounted *inside* the scroll content: as a background on the
/// `ScrollView` itself the probe is a sibling of the scroll view, and
/// `enclosingScrollView` would find nothing.
private struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        // Deferred: the view has no enclosing scroll view until SwiftUI has
        // put it in the hierarchy.
        DispatchQueue.main.async { configure(from: probe) }
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(from: view) }
    }

    private func configure(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        if !(scrollView.verticalScroller is SlotlessScroller) {
            let scroller = SlotlessScroller()
            scroller.controlSize = .small
            scrollView.verticalScroller = scroller
        }
        scrollView.hasVerticalScroller = true
    }
}

/// Scroller that draws its knob but not the slot behind it.
private final class SlotlessScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Intentionally empty: the panel is the background.
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollToBottomButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.thickMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.separator))
                .scaleEffect(isHovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .help("Scroll to latest")
        .accessibilityLabel("Scroll to latest message")
    }
}

/// Shown before the first message.
struct EmptyStateView: View {
    @EnvironmentObject private var chat: ChatViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Colors.subtleText)

            Text("Ask \(settings.model.displayName) anything")
                .font(.system(size: 15, weight: .medium))

            if !chat.status.canSend {
                Text(chat.status.remedy ?? chat.status.summary)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.errorTint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            } else {
                Text("Drop in files or paste an image to include them.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
