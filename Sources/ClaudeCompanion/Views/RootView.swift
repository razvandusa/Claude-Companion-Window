import SwiftUI
import UniformTypeIdentifiers

/// The panel's content: header, transcript, composer, on a translucent
/// rounded surface.
struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var chat: ChatViewModel

    @State private var isTargetedForDrop = false

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView()

            TranscriptView()

            ComposerView()
        }
        .background(alignment: .top) {
            AmbientBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                environment.panelController?.beginModalPresentation()
            } else {
                environment.panelController?.endModalPresentation()
                Task { await chat.refreshStatus() }
            }
        }
        .preferredColorScheme(nil)
    }
}

/// The panel's surface: window material, a tint over it, and a warm wash
/// falling from the top edge.
///
/// The wash is what keeps the header from reading as a separate bar now that
/// the divider under it is gone — the chrome and the transcript share one
/// continuous field of colour.
private struct AmbientBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView(material: .hudWindow)

            Theme.Colors.surface

            LinearGradient(
                stops: [
                    .init(color: Theme.Colors.ambient, location: 0),
                    .init(color: Theme.Colors.ambient.opacity(0.55), location: 0.35),
                    .init(color: Theme.Colors.ambient.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Theme.Metrics.ambientHeight)
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
