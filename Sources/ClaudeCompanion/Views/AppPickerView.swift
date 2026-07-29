import SwiftUI
import AppKit

/// The "Work With" popover: search, then a list of apps to attach.
///
/// Adding an app doesn't capture anything yet — the window is grabbed when the
/// message is sent, so what the model sees is current.
struct AppPickerView: View {
    /// Observed rather than reached for through ``AppEnvironment``, so the list
    /// actually redraws when the directory finishes refreshing.
    @ObservedObject var directory: AppDirectory

    @EnvironmentObject private var chat: ChatViewModel

    @State private var query = ""
    @State private var hoveredID: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider().overlay(Theme.Colors.separator)

            list
        }
        .frame(width: 320, height: 340)
        .background(Theme.Colors.popoverFill)
        .onAppear { directory.refresh() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.subtleText)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    // MARK: - List

    private var apps: [CompanionApp] {
        AppDirectory.filter(directory.apps, query: query)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                sectionHeader

                ForEach(apps) { app in
                    AppRow(
                        app: app,
                        icon: directory.icon(for: app),
                        isAdded: chat.isWorkingWith(app),
                        isHighlighted: hoveredID == app.id
                    ) {
                        toggle(app)
                    }
                    .onHover { hovering in
                        hoveredID = hovering ? app.id : (hoveredID == app.id ? nil : hoveredID)
                    }
                }

                if apps.isEmpty {
                    Text("No apps match “\(query)”.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.subtleText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 5) {
            Text("Work With")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.subtleText)

            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.subtleText)
                .help("The app's front window is captured and attached when you send a message.")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func toggle(_ app: CompanionApp) {
        if chat.isWorkingWith(app) {
            chat.removeWorkingWithApp(id: app.id)
        } else {
            chat.addWorkingWithApp(app)
        }
    }
}

/// One row: icon, name, running state, and an Add/Added affordance.
private struct AppRow: View {
    let app: CompanionApp
    let icon: NSImage
    let isAdded: Bool
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 14))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isAdded {
                    Text("Added")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.subtleText)
                } else if isHighlighted {
                    Text("Add")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Colors.controlActive)
                    .opacity(isHighlighted || isAdded ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAdded ? "\(title), added" : "Add \(title)")
    }

    /// Matches the picker's "Name • Not running" form.
    private var title: String {
        guard let state = app.runningStateLabel else { return app.name }
        return "\(app.name) • \(state)"
    }
}
