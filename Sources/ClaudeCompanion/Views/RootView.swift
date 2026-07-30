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
    /// Off entirely while a sheet is up: the panel is resized to exactly
    /// contain the sheet, so the only part of the window left uncovered is the
    /// strip a sheet is inset below. Drawing the surface there would put a band
    /// of panel above the sheet with nothing in it.
    private var showsPanelChrome: Bool {
        environment.isExpanded && !environment.isShowingSettings
    }

    var body: some View {
        Group {
            if environment.isShowingSettings {
                // Settings fills the panel rather than arriving as a sheet.
                // A sheet is always inset below the titlebar and is grown to
                // fit by AppKit, which leaves strips of window showing above
                // and below it however precisely the window is sized. Filling
                // the panel means there is nothing left over to show.
                SettingsView()
                    .environmentObject(environment)
                    .environmentObject(environment.settings)
                    .environmentObject(chat)
                    .transition(.opacity)
            } else {
                conversation
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous))
        .overlay {
            if showsPanelChrome || environment.isShowingSettings {
                RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .animation(Theme.Animations.quick, value: environment.isShowingSettings)
        // On the outer view, not on the conversation: the conversation is
        // removed while Settings is up, so an observer attached there would
        // never see it close.
        .onChange(of: environment.isShowingSettings) { _, isShowing in
            if isShowing {
                // The window resizes to Settings' size and back again. It is
                // held in a modal state throughout so a focus change doesn't
                // read as a click outside and dismiss the panel.
                environment.panelController?.makeRoomForSheet(SettingsView.preferredSize)
                environment.panelController?.beginModalPresentation()
            } else {
                environment.panelController?.endModalPresentation()
                Task { await chat.refreshStatus() }
            }
        }
        .preferredColorScheme(nil)
    }

    /// The panel's normal contents.
    private var conversation: some View {
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
