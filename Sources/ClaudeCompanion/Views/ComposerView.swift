import SwiftUI
import AppKit

/// The input surface: one rounded container holding the staged attachments,
/// the growing text view, and a row of controls beneath it.
struct ComposerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var chat: ChatViewModel
    @EnvironmentObject private var settings: SettingsStore

    @State private var editorHeight: CGFloat = 22
    @State private var isShowingAppPicker = false
    /// Backing view of the `+`, used to anchor its menu.
    @State private var attachAnchor: NSView?

    var body: some View {
        VStack(spacing: 8) {
            if let message = chat.transientMessage {
                TransientBanner(message: message) {
                    chat.transientMessage = nil
                }
            }

            container

            // The meter belongs to a conversation in progress; on the bare
            // bar it is just noise under an empty field.
            if settings.showTokenUsage, environment.isExpanded, !environment.isShowingSettings {
                TokenUsageView()
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
        .padding(.bottom, 14)
        .background {
            // Reports the collapsed bar's natural height so the panel can size
            // itself to the composer, including when a draft grows it.
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ComposerHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(ComposerHeightKey.self) { height in
            guard height > 0 else { return }
            environment.collapsedContentHeight = height + 12
        }
        .animation(Theme.Animations.quick, value: chat.pendingAttachments.count)
        .animation(Theme.Animations.quick, value: chat.workingWithApps.count)
        .animation(Theme.Animations.quick, value: chat.transientMessage)
    }

    private var container: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chat.workingWithApps.isEmpty {
                WorkingWithStrip(apps: chat.workingWithApps) { id in
                    chat.removeWorkingWithApp(id: id)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !chat.pendingAttachments.isEmpty {
                AttachmentStrip(attachments: chat.pendingAttachments) { id in
                    withAnimation(Theme.Animations.quick) { chat.removeAttachment(id: id) }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            textEntry
            controlRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .background { containerBackground }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.composerCornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.composerStroke)
        }
    }

    /// Inside the expanded panel the composer is a lighter well on a surface
    /// that already exists. Collapsed, it *is* the window, so it has to bring
    /// the material and tint with it or there would be nothing behind the text.
    @ViewBuilder
    private var containerBackground: some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Metrics.composerCornerRadius,
            style: .continuous
        )

        if environment.isExpanded {
            shape.fill(Theme.Colors.composerFill)
        } else {
            ZStack {
                VisualEffectView(material: .hudWindow)
                Theme.Colors.surface
            }
            .clipShape(shape)
        }
    }

    // MARK: - Text

    private var textEntry: some View {
        ZStack(alignment: .topLeading) {
            if chat.draft.isEmpty {
                Text(placeholder)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.subtleText)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }

            GrowingTextEditor(
                text: $chat.draft,
                height: $editorHeight,
                isEnabled: !chat.isStreaming,
                onSubmit: { chat.send() },
                onPasteAttachments: { chat.apply($0) }
            )
            .frame(height: editorHeight)
        }
        .padding(.horizontal, 2)
    }

    private var placeholder: String {
        switch chat.status {
        case .signedIn: "Ask anything"
        case .signedOut: "Sign in to Claude Code to start"
        case .notInstalled: "Set the Claude Code path in Settings"
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: 2) {
            attachMenu

            ComposerIconButton(
                systemImage: "globe",
                isActive: settings.isWebSearchEnabled,
                tint: settings.isWebSearchEnabled ? .accentColor : nil,
                help: settings.isWebSearchEnabled ? "Web search on" : "Search the web",
                action: {
                    withAnimation(Theme.Animations.quick) {
                        settings.isWebSearchEnabled.toggle()
                    }
                }
            )
            .accessibilityLabel("Search the web")
            .accessibilityValue(settings.isWebSearchEnabled ? "On" : "Off")

            appsButton

            Spacer(minLength: 8)

            MicButton(dictation: environment.dictation)

            SendButton(isStreaming: chat.isStreaming) {
                if chat.isStreaming {
                    chat.cancelStreaming()
                } else {
                    chat.send()
                }
            }
            .disabled(!chat.canSend && !chat.isStreaming)
            .padding(.leading, 4)
        }
    }

    private var attachMenu: some View {
        ComposerIconButton(
            help: "Add files, screenshots or photos",
            action: presentAttachmentMenu
        ) {
            Image(systemName: "plus")
                .font(Theme.Fonts.plusIcon)
        }
        .disabled(chat.isCapturing)
        .accessibilityLabel("Add attachment")
        .background { MenuAnchor(view: $attachAnchor) }
    }

    private func presentAttachmentMenu() {
        guard let attachAnchor else { return }

        // A menu takes key window status while it is tracking.
        environment.panelController?.beginModalPresentation()
        defer { environment.panelController?.endModalPresentation() }

        AttachmentMenu.present(AttachmentMenu.menu(for: chat), from: attachAnchor)
    }

    private var appsButton: some View {
        ComposerIconButton(
            isActive: isShowingAppPicker || !chat.workingWithApps.isEmpty,
            help: "Work with an app",
            action: { isShowingAppPicker = true }
        ) {
            AppsGlyph()
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 17, height: 17)
        }
        .accessibilityLabel("Work with an app")
        .popover(isPresented: $isShowingAppPicker, arrowEdge: .top) {
            AppPickerView(directory: environment.appDirectory)
                .environmentObject(chat)
        }
        // A popover takes key window status, which would otherwise read as a
        // click outside and dismiss the whole panel behind it.
        .onChange(of: isShowingAppPicker) { _, isShowing in
            if isShowing {
                environment.panelController?.beginModalPresentation()
            } else {
                environment.panelController?.endModalPresentation()
            }
        }
    }

}

/// Mic button, split out so the dictation service is properly observed rather
/// than merely reached through the environment object.
private struct MicButton: View {
    @ObservedObject var dictation: DictationService

    @EnvironmentObject private var chat: ChatViewModel

    var body: some View {
        ComposerIconButton(
            systemImage: dictation.isRecording ? "mic.fill" : "mic",
            isActive: dictation.isRecording,
            tint: dictation.isRecording ? .red : nil,
            help: dictation.isRecording ? "Stop dictation" : "Dictate",
            action: { dictation.toggle(baseText: chat.draft) }
        )
        .accessibilityLabel("Dictate")
        .accessibilityValue(dictation.isRecording ? "Recording" : "Off")
        .onAppear {
            // Transcription replaces the draft wholesale: the service tracks
            // what was already typed and prepends it.
            dictation.onTranscript = { text in chat.draft = text }
            dictation.onError = { reason in chat.transientMessage = reason }
        }
    }
}

/// Carries the composer's measured height up to the panel.
private struct ComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Dismissible inline notice for non-fatal problems.
private struct TransientBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text(message)
                .font(Theme.Fonts.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(Theme.Colors.subtleText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Colors.composerFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .transition(.opacity)
    }
}

/// Context-usage meter under the composer.
struct TokenUsageView: View {
    @EnvironmentObject private var chat: ChatViewModel

    private var fraction: Double {
        guard chat.contextWindow > 0 else { return 0 }
        return min(1, Double(chat.estimatedContextTokens) / Double(chat.contextWindow))
    }

    private var tint: Color {
        switch fraction {
        case ..<0.75: Theme.Colors.subtleText
        case ..<0.9: .orange
        default: .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 52, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: 52 * fraction, height: 3)
                }

            Text(usageLabel)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .monospacedDigit()

            Spacer()

            Text(chat.isStreaming ? "Esc to stop" : "Return to send · Shift-Return for a new line")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.subtleText)
        }
        .animation(Theme.Animations.quick, value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context used: \(usageLabel)")
    }

    private var usageLabel: String {
        let used = chat.estimatedContextTokens
        guard used > 0 else { return "0 tokens" }
        return "\(Self.compact(used)) / \(Self.compact(chat.contextWindow)) tokens"
    }

    private static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: "\(value / 1_000)K"
        default: "\(value)"
        }
    }
}
