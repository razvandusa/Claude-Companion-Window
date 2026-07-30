import SwiftUI
import UniformTypeIdentifiers

/// The panel's content: header, transcript, composer, on a translucent
/// rounded surface.
struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var chat: ChatViewModel

    @State private var isTargetedForDrop = false

    /// Whether to draw the full panel rather than the bare composer.
    ///
    /// Tracks the window's own size, which is why a sheet forces it on: the
    /// window can't shrink under an open sheet, so collapsing the content
    /// would strand a lone composer in a tall, empty, borderless window. The
    /// panel resizes and this reverts together, once the sheet closes.
    private var showsPanelChrome: Bool {
        environment.isExpanded || environment.isShowingSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed, the panel is only the composer: no header to dismiss
            // a conversation that doesn't exist yet, and no empty transcript.
            if showsPanelChrome {
                ChatHeaderView()

                TranscriptView()
            } else {
                Spacer(minLength: 12)
            }

            ComposerView()
        }
        // Collapsed there is no panel — only the composer, floating on its own.
        // Drawing the surface and its border around it would put a second box
        // around a bar that is already a box.
        .background {
            if showsPanelChrome {
                PanelBackground()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous))
        .overlay {
            if showsPanelChrome {
                RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .overlay {
            if isTargetedForDrop {
                DropTargetOverlay()
                    .transition(.opacity)
            }
        }
        .animation(Theme.Animations.quick, value: isTargetedForDrop)
        // Files dropped anywhere on the panel attach to the next message.
        .onDrop(of: AttachmentLoader.supportedDropTypes, isTargeted: $isTargetedForDrop) { providers in
            Task {
                let result = await AttachmentLoader.load(from: providers)
                chat.addAttachments(result.attachments)
                if let failure = result.failureDescription {
                    chat.transientMessage = failure
                }
            }
            return true
        }
        .sheet(isPresented: $environment.isShowingSettings) {
            SettingsView()
                .environmentObject(environment)
                .environmentObject(environment.settings)
                .environmentObject(chat)
        }
        .onChange(of: environment.isShowingSettings) { _, isShowing in
            // A sheet takes key window status; without this the panel would
            // treat that as a click-outside and dismiss itself.
            if isShowing {
                // Order matters: the panel has to be big enough to contain the
                // sheet before it appears, or AppKit grows the window itself
                // and leaves it that size once the sheet closes.
                environment.panelController?.makeRoomForSheet(SettingsView.sheetSize)
                environment.panelController?.beginModalPresentation()
            } else {
                environment.panelController?.endModalPresentation()
                Task { await chat.refreshStatus() }
            }
        }
        .preferredColorScheme(nil)
    }
}

/// The panel's surface: window material with a neutral tint over it.
///
/// One flat field top to bottom, with no divider under the header, so the
/// chrome and the transcript read as a single surface.
private struct PanelBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)

            Theme.Colors.surface
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Shown while a drag is hovering over the panel.
private struct DropTargetOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .overlay {
                Label("Drop to attach", systemImage: "paperclip")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thickMaterial, in: Capsule())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return RootView()
        .environmentObject(environment)
        .environmentObject(environment.settings)
        .environmentObject(environment.chat)
        .frame(width: 480, height: 640)
}
