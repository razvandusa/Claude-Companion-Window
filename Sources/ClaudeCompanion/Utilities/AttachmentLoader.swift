import AppKit
import UniformTypeIdentifiers

/// Turns dropped files, pasted images and picked URLs into ``Attachment``
/// values the API can accept.
///
/// Images are downscaled and recompressed here rather than at send time so the
/// cost of a large screenshot is paid once, and transcripts stay small on disk.
enum AttachmentLoader {

    /// Longest edge kept for an attached image. Larger images are billed for
    /// more tokens without helping the model on typical screenshots.
    static let maximumImageEdge: CGFloat = 1_568

    /// Largest text file that will be inlined into a message.
    static let maximumTextBytes = 256 * 1024

    static let supportedDropTypes: [UTType] = [.fileURL, .image, .plainText]

    /// Outcome of importing a single item.
    enum Outcome {
        case success(Attachment)
        /// User-facing reason the item was skipped.
        case failure(String)
    }

    struct Result {
        var attachments: [Attachment] = []
        var rejected: [String] = []

        var failureDescription: String? {
            guard !rejected.isEmpty else { return nil }
            if rejected.count == 1 { return rejected[0] }
            return "\(rejected.count) items couldn't be attached."
        }
    }

    // MARK: - Drag and drop

    static func load(from providers: [NSItemProvider]) async -> Result {
        var result = Result()

        for provider in providers {
            if let url = await provider.loadFileURL() {
                switch loadFile(at: url) {
                case .success(let attachment): result.attachments.append(attachment)
                case .failure(let reason): result.rejected.append(reason)
                }
                continue
            }

            if let data = await provider.loadData(for: .image),
               let attachment = makeImageAttachment(from: data, filename: "Pasted Image") {
                result.attachments.append(attachment)
                continue
            }

            result.rejected.append("An item couldn't be read.")
        }

        return result
    }

    // MARK: - Files

    static func loadFile(at url: URL) -> Outcome {
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard !isDirectory else {
            return .failure("Folders can't be attached.")
        }

        guard let data = try? Data(contentsOf: url) else {
            return .failure("\(name) couldn't be read.")
        }

        if type?.conforms(to: .image) == true {
            guard let attachment = makeImageAttachment(from: data, filename: name) else {
                return .failure("\(name) isn't a supported image.")
            }
            return .success(attachment)
        }

        // Anything that decodes as UTF-8 is treated as text, which covers source
        // files and config formats without needing an exhaustive type list.
        guard data.count <= maximumTextBytes else {
            return .failure("\(name) is too large to attach (limit \(maximumTextBytes / 1024) KB).")
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return .failure("\(name) isn't a text or image file.")
        }

        return .success(Attachment(
            filename: name,
            kind: .text,
            mediaType: "text/plain",
            data: Data(text.utf8)
        ))
    }

    // MARK: - Pasteboard

    /// Reads an image or file list from the general pasteboard.
    ///
    /// Returns `nil` when the pasteboard holds only plain text, so the text
    /// view's own paste handling takes over.
    static func loadFromPasteboard(_ pasteboard: NSPasteboard = .general) -> Result? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            var result = Result()
            for url in urls {
                switch loadFile(at: url) {
                case .success(let attachment): result.attachments.append(attachment)
                case .failure(let reason): result.rejected.append(reason)
                }
            }
            return result
        }

        // Rich text copied from a browser often carries an image representation
        // alongside the string. If there's any text on the pasteboard, the user
        // meant to paste text — only a pure-image pasteboard becomes an
        // attachment.
        guard !pasteboard.canReadObject(forClasses: [NSString.self]) else { return nil }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type) else { continue }
            guard let attachment = makeImageAttachment(from: data, filename: "Pasted Image") else {
                continue
            }
            return Result(attachments: [attachment])
        }

        return nil
    }

    // MARK: - Image normalisation

    /// Downscales to ``maximumImageEdge`` and re-encodes as PNG.
    static func makeImageAttachment(from data: Data, filename: String) -> Attachment? {
        guard let image = NSImage(data: data) else { return nil }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(1, maximumImageEdge / max(size.width, size.height))
        let targetSize = NSSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        guard let encoded = encodePNG(image, targetSize: targetSize) else { return nil }

        return Attachment(
            filename: normalizedName(filename),
            kind: .image,
            mediaType: "image/png",
            data: encoded
        )
    }

    private static func encodePNG(_ image: NSImage, targetSize: NSSize) -> Data? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        representation.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        return representation.representation(using: .png, properties: [:])
    }

    private static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "image.png" }
        return trimmed
    }
}

// MARK: - NSItemProvider bridging

private extension NSItemProvider {
    func loadFileURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        guard let data = await loadData(for: .fileURL) else { return nil }
        return URL(dataRepresentation: data, relativeTo: nil)
    }

    func loadData(for type: UTType) async -> Data? {
        guard hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
