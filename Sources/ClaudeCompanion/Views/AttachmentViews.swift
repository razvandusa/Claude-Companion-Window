import SwiftUI
import AppKit

/// Horizontal run of attachment chips.
struct AttachmentStrip: View {
    let attachments: [Attachment]
    var alignment: HorizontalAlignment = .leading
    var onRemove: ((UUID) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if alignment == .trailing { Spacer(minLength: 0) }
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment, onRemove: onRemove)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

/// Horizontal run of the apps picked in "Work With".
struct WorkingWithStrip: View {
    let apps: [CompanionApp]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(apps) { app in
                    WorkingWithChip(app: app) { onRemove(app.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One picked app. Its window is captured when the message is sent, so the
/// chip is a promise rather than a thumbnail.
private struct WorkingWithChip: View {
    let app: CompanionApp
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable()
                .frame(width: 16, height: 16)

            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.Colors.subtleText)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.5)
            .accessibilityLabel("Stop working with \(app.name)")
        }
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .background(
            Theme.Colors.controlActive,
            in: Capsule()
        )
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working with \(app.name)")
    }
}

/// One attachment: image thumbnail or file glyph, name, size, optional remove.
struct AttachmentChip: View {
    let attachment: Attachment
    var onRemove: ((UUID) -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            thumbnail

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.filename)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.subtleText)
            }
            .frame(maxWidth: 130, alignment: .leading)

            if let onRemove {
                Button {
                    onRemove(attachment.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.subtleText)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.5)
                .help("Remove attachment")
                .accessibilityLabel("Remove \(attachment.filename)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Colors.separator)
        }
        .onHover { hovering in
            withAnimation(Theme.Animations.quick) { isHovering = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.filename), \(attachment.formattedSize)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch attachment.kind {
        case .image:
            if let image = NSImage(data: attachment.data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                glyph("photo")
            }
        case .text:
            glyph("doc.text")
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12))
            .foregroundStyle(Theme.Colors.subtleText)
            .frame(width: 24, height: 24)
            .background(
                Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }
}
