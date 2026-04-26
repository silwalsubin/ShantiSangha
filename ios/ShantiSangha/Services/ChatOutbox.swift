import Foundation

/// One pending text send waiting to be flushed to the API. Created
/// when a `sendText` call fails (or fires while the device is offline)
/// and replayed on the next reconnect / next chat re-open.
///
/// Scope: text only for v1. Image and voice sends need a presigned
/// upload URL fetched at compose time; deferring them requires holding
/// the binary on disk and re-fetching the URL on flush, which is more
/// machinery than we want for "some level" of offline support.
struct PendingMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let body: String
    let replyToMessageId: UUID?
    let createdAt: Date
    /// Last error message if a send attempt failed permanently. When
    /// non-nil the bubble renders as "Tap to retry"; nil = still
    /// in-flight or freshly enqueued.
    var lastError: String?

    init(
        id: UUID = UUID(),
        body: String,
        replyToMessageId: UUID? = nil,
        createdAt: Date = Date(),
        lastError: String? = nil
    ) {
        self.id = id
        self.body = body
        self.replyToMessageId = replyToMessageId
        self.createdAt = createdAt
        self.lastError = lastError
    }
}

/// On-disk pending-send queue, one JSON file per friendship under
/// Application Support. Mirrors the shape of `ChatCache` so both
/// caches live alongside each other and share the same atomic-write
/// pattern. Saves are fire-and-forget on a serial background queue.
enum ChatOutbox {
    private static let writeQueue = DispatchQueue(label: "chat.outbox.write", qos: .utility)

    private static let encoder = JSONEncoder()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static var dir: URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true) else {
            return nil
        }
        let target = appSupport.appendingPathComponent("ChatOutbox", isDirectory: true)
        if !fm.fileExists(atPath: target.path) {
            try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        }
        return target
    }

    private static func file(for friendshipId: UUID) -> URL? {
        dir?.appendingPathComponent("\(friendshipId.uuidString.lowercased()).json")
    }

    static func load(friendshipId: UUID) -> [PendingMessage] {
        guard let url = file(for: friendshipId),
              let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([PendingMessage].self, from: data) else {
            return []
        }
        return items
    }

    static func save(friendshipId: UUID, items: [PendingMessage]) {
        // Capture-by-value before crossing into the background queue so
        // mutations on the @MainActor side don't race with the encode.
        let snapshot = items
        writeQueue.async {
            guard let url = file(for: friendshipId) else { return }
            do {
                if snapshot.isEmpty {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                // Silent — outbox failures shouldn't surface.
            }
        }
    }

    static func clearAll() {
        guard let dir = dir else { return }
        writeQueue.async { try? FileManager.default.removeItem(at: dir) }
    }
}
