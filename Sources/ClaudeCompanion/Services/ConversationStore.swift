import Foundation
import OSLog

/// Persistence for conversation transcripts.
///
/// Declared as a protocol so the chat view model can be constructed with an
/// in-memory double in tests.
protocol ConversationStoring: Sendable {
    func loadAll() async throws -> [Conversation]
    func save(_ conversation: Conversation) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

/// Stores one JSON file per conversation under Application Support.
///
/// One file per conversation (rather than a single archive) keeps writes cheap
/// during streaming and means a single corrupted transcript can't take the
/// whole history down with it.
actor FileConversationStore: ConversationStoring {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "ConversationStore")

    /// Transcripts older than this are pruned on load to bound disk usage.
    private let retentionLimit = 200

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(using: fileManager)

        // Fractional seconds matter: transcripts are ordered by `updatedAt`, and
        // plain `.iso8601` truncates to whole seconds, so two conversations
        // touched in the same second would sort arbitrarily and a saved
        // conversation would not compare equal to the one reloaded from disk.
        // Format styles rather than `ISO8601DateFormatter`: they're value types,
        // so the encoding closures stay `Sendable`.
        let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        // Transcripts written before fractional seconds were adopted.
        let legacy = Date.ISO8601FormatStyle()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(precise.format(date))
        }
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? precise.parse(text) { return date }
            if let date = try? legacy.parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognised date format: \(text)"
            ))
        }
        self.decoder = decoder
    }

    static func defaultDirectory(using fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent(AppInfo.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("Conversations", isDirectory: true)
    }

    func loadAll() async throws -> [Conversation] {
        try ensureDirectoryExists()

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var conversations: [Conversation] = []
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                conversations.append(try decoder.decode(Conversation.self, from: data))
            } catch {
                // A single unreadable transcript must not block startup. Move it
                // aside so it stops being retried and the user can recover it.
                logger.error("Skipping unreadable transcript \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? quarantine(url)
            }
        }

        conversations.sort { $0.updatedAt > $1.updatedAt }

        if conversations.count > retentionLimit {
            for stale in conversations[retentionLimit...] {
                try? fileManager.removeItem(at: fileURL(for: stale.id))
            }
            conversations = Array(conversations.prefix(retentionLimit))
        }

        return conversations
    }

    func save(_ conversation: Conversation) async throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(conversation)
        try data.write(to: fileURL(for: conversation.id), options: .atomic)
    }

    func delete(id: UUID) async throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deleteAll() async throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
        try ensureDirectoryExists()
    }

    // MARK: - Private

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func quarantine(_ url: URL) throws {
        let destination = url.deletingPathExtension().appendingPathExtension("corrupt")
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: url, to: destination)
    }
}

/// In-memory store used by tests and previews.
actor InMemoryConversationStore: ConversationStoring {
    private var storage: [UUID: Conversation] = [:]

    init(seed: [Conversation] = []) {
        for conversation in seed { storage[conversation.id] = conversation }
    }

    func loadAll() async throws -> [Conversation] {
        storage.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversation: Conversation) async throws {
        storage[conversation.id] = conversation
    }

    func delete(id: UUID) async throws {
        storage[id] = nil
    }

    func deleteAll() async throws {
        storage.removeAll()
    }
}
