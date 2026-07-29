import SwiftUI
import KeyboardShortcuts

/// Preferences sheet presented over the panel.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var chat: ChatViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var executablePathField = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    accountSection
                    modelSection
                    shortcutSection
                    behaviorSection
                    dataSection
                    aboutSection
                }
                .padding(18)
            }
        }
        .frame(width: 460, height: 560)
        .background(VisualEffectView(material: .windowBackground))
        .onAppear {
            executablePathField = UserDefaults.standard
                .string(forKey: ClaudeCodeLocator.overrideDefaultsKey) ?? ""
            Task { await chat.refreshStatus() }
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private var accountSection: some View {
        SettingsSection("Claude Account") {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(chat.status.summary)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let remedy = chat.status.remedy {
                Text(remedy)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Replies run through the Claude Code CLI, so they use your Claude subscription rather than API credits. `ANTHROPIC_API_KEY` is removed from its environment to keep it that way.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.subtleText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Path to `claude`")
                    .font(Theme.Fonts.body)

                HStack(spacing: 8) {
                    TextField("Detected automatically", text: $executablePathField)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.caption)
                        .onSubmit(saveExecutablePath)

                    Button("Save", action: saveExecutablePath)
                }

                Text("Only needed if the app can't find Claude Code on its own.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(statusIsError ? Theme.Colors.errorTint : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modelSection: some View {
        SettingsSection("Model") {
            Picker("Model", selection: $settings.model) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(settings.model.summary)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.subtleText)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show thinking", isOn: $settings.isThinkingEnabled)
                .help("Shows a summary of Claude's reasoning above each reply. Use Effort to control how much it reasons.")

            Picker("Effort", selection: $settings.effort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.effort.summary)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.subtleText)

            HStack {
                Text("Max response length")
                    .font(Theme.Fonts.body)
                Spacer()
                Text("\(settings.effectiveMaxTokens) tokens")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(settings.maxTokens) },
                    set: { settings.maxTokens = Int($0) }
                ),
                in: 1_024...Double(settings.model.maximumOutputTokens),
                step: 1_024
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text("System prompt")
                    .font(Theme.Fonts.body)
                TextEditor(text: $settings.systemPrompt)
                    .font(Theme.Fonts.body)
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                Text("Applied to every new message in every conversation.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.subtleText)
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection("Global Shortcut") {
            HStack {
                Text("Show or hide the window")
                    .font(Theme.Fonts.body)
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleCompanion)
            }
            Text("Works from any app. Default is ⌥Space.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.subtleText)
        }
    }

    private var behaviorSection: some View {
        SettingsSection("Behavior") {
            Toggle("Dismiss when clicking outside", isOn: $settings.dismissOnClickOutside)
            Toggle("Show token usage", isOn: $settings.showTokenUsage)
            Toggle("Launch at login", isOn: launchAtLoginBinding)
        }
    }

    private var dataSection: some View {
        SettingsSection("Conversations") {
            Text("Transcripts are stored locally in Application Support.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.subtleText)

            Button("Delete all conversations", role: .destructive) {
                isConfirmingClear = true
            }
            .confirmationDialog(
                "Delete all conversations?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: clearConversations)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every stored transcript. It can't be undone.")
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            Text("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.subtleText)
        }
    }

    // MARK: - Bindings and actions

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                if let failure = LoginItemService.setEnabled(newValue) {
                    statusMessage = failure
                    statusIsError = true
                    settings.launchAtLogin = LoginItemService.isEnabled
                } else {
                    settings.launchAtLogin = newValue
                }
            }
        )
    }

    private var statusIcon: String {
        chat.status.canSend ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        chat.status.canSend ? .green : Theme.Colors.errorTint
    }

    private func saveExecutablePath() {
        let trimmed = executablePathField.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = UserDefaults.standard

        if trimmed.isEmpty {
            defaults.removeObject(forKey: ClaudeCodeLocator.overrideDefaultsKey)
        } else {
            defaults.set(trimmed, forKey: ClaudeCodeLocator.overrideDefaultsKey)
        }

        Task {
            await chat.refreshStatus()
            statusIsError = !chat.status.canSend
            statusMessage = trimmed.isEmpty
                ? "Cleared. Looking for Claude Code in the usual places."
                : (chat.status.canSend ? "Found Claude Code." : "Nothing usable at that path.")
        }
    }

    private func clearConversations() {
        Task {
            try? await environment.conversationStore.deleteAll()
            await MainActor.run {
                chat.startNewConversation()
                statusMessage = "All conversations deleted."
                statusIsError = false
            }
        }
    }
}

/// Titled group used throughout Settings.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.subtleText)
                .textCase(.uppercase)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
