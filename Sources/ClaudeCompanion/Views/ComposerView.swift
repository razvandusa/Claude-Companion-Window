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

    var body: some View {
        VStack(spacing: 8) {
            if let message = chat.transientMessage {
                TransientBanner(message: message) {
                    chat.transientMessage = nil
                }
            }

            container

            if settings.showTokenUsage {
                TokenUsageView()
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
        .padding(.bottom, 14)
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
        .background(
            Theme.Colors.composerFill,
            in: RoundedRectangle(cornerRadius: Theme.Metrics.composerCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.composerCornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.composerStroke)
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
        Menu {
            Button("Upload file") { chat.presentOpenPanel(imagesOnly: false) }
            Button("Upload photo") { chat.presentOpenPanel(imagesOnly: true) }

            Menu("Take screenshot") {
                Button("Selection…") { chat.attachScreenshot(.selection) }
                Button("Window…") { chat.attachScreenshot(.window) }
                Button("Entire Screen") { chat.attachScreenshot(.fullScreen) }
            }

            Button("Take photo") { chat.attachCameraPhoto() }
        } label: {
            Image(systemName: "plus")
                .font(Theme.Fonts.controlIcon)
                .foregroundStyle(Theme.Colors.controlIcon)
                .frame(width: Theme.Metrics.composerControl, height: Theme.Metrics.composerControl)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(chat.isCapturing)
        .help("Add files, screenshots or photos")
        .accessibilityLabel("Add attachment")
    }

    private var appsButton: some View {
        ComposerIconButton(
            isActive: isShowingAppPicker || !chat.workingWithApps.isEmpty,
            help: "Work with an app",
            action: { isShowingAppPicker = true }
        ) {
            AppsGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
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
