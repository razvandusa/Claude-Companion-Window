import SwiftUI

/// Top bar: dismiss on the left, history and new chat on the right.
///
/// Deliberately holds no title. The conversation is identified by what is in
/// it, and the bar stays quiet enough to be a drag handle for the panel.
struct ChatHeaderView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var chat: ChatViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            CloseButton { environment.panelController?.hide() }

            Spacer(minLength: 8)

            historyMenu

            HeaderButton(
                systemImage: "square.and.pencil",
                help: "New chat",
                action: { chat.startNewConversation() }
            )
            .accessibilityLabel("New chat")
            .disabled(!chat.hasMessages)
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.headerHeight)
        // Lets the whole bar act as a drag handle for the panel.
        .contentShape(Rectangle())
    }

    /// Recents, the model picker and Settings, behind one glyph — the bar in
    /// the design has room for two controls, and new chat owns the other one.
    private var historyMenu: some View {
        Menu {
            Section("Model") {
                Picker("Model", selection: $settings.model) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if !chat.recentConversations.isEmpty {
                Section("Recent") {
                    ForEach(chat.recentConversations.prefix(8)) { conversation in
                        Button {
                            chat.open(conversation)
                        } label: {
                            Text(conversation.title)
                        }
                    }
                }
            }

            Divider()

            Button("Settings…") { environment.isShowingSettings = true }
        } label: {
            Image(systemName: "square.on.square")
                .font(.system(size: 15, weight: .regular))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 26)
        .foregroundStyle(Theme.Colors.controlIcon)
        .accessibilityLabel("History, model and settings")
        .help("History, model and settings")
    }
}

/// Filled circular dismiss button in the top-left corner.
private struct CloseButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Colors.controlIcon)
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(Theme.Colors.controlActive)
                        .overlay {
                            Circle()
                                .fill(Theme.Colors.hoverHighlight)
                                .opacity(isHovering ? 1 : 0)
                        }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .help("Close (esc)")
        .accessibilityLabel("Close")
    }
}

/// Small square icon button with a hover highlight, used across the chrome.
struct HeaderButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 30, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.Colors.controlActive.opacity(isHovering && isEnabled ? 1 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Theme.Colors.controlIcon : Theme.Colors.controlIcon.opacity(0.4))
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .help(help)
    }
}
