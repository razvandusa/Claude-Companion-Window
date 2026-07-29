import Foundation

/// What kind of content an attachment carries, which decides how it is encoded
/// into a Messages API content block.
enum AttachmentKind: String, Codable, Sendable {
    /// Sent as an `image` content block (base64).
    case image
    /// Sent as a `text` content block wrapped in a filename header.
    case text
}

/// A file or pasted image the user attached to a message.
///
/// Attachments are stored inline with the conversation. Images are downscaled
/// and recompressed on import (see ``AttachmentLoader``) so a transcript stays
/// a reasonable size on disk.
struct Attachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var filename: String
    var kind: AttachmentKind
    /// IANA media type — `image/png`, `image/jpeg`, `text/plain`, …
    var mediaType: String
    var data: Data

    init(
        id: UUID = UUID(),
        filename: String,
        kind: AttachmentKind,
        mediaType: String,
        data: Data
    ) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.mediaType = mediaType
        self.data = data
    }

    var byteCount: Int { data.count }

    /// UTF-8 contents for text attachments; `nil` for images.
    var textContents: String? {
        guard kind == .text else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Human-readable size for the attachment chip.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// Media types the Anthropic API accepts for image blocks.
    static let supportedImageMediaTypes: Set<String> = [
        "image/jpeg", "image/png", "image/gif", "image/webp"
    ]
}
