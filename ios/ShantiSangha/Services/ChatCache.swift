import Foundation

/// Lightweight on-disk cache of recent chat messages, one JSON file per
/// friendship under Application Support. Lets `FriendChatView` paint
/// instantly from the last-known thread when it opens (and read history
/// while offline) before the API refresh resolves.
///
/// Trade-offs vs SwiftData / CoreData:
///   - The file is small (~50KB worst case at the cap), atomic writes
///     are sufficient, and there's no schema migration ceremony — when
///     `FriendMessage` gains a Codable field, old caches simply fail to
///     decode and we fall back to empty (next refresh repopulates).
///   - No relational queries, no per-message indices. We don't need
///     either: a thread is loaded as a single ordered array.
///
/// What this caches:
///   - The most recent `cap` messages per friendship, by `sentAt`.
///   - All Codable fields on FriendMessage including reply previews,
///     read/edited/deleted timestamps, and media URLs.
///
/// What this does NOT cache:
///   - Outgoing messages waiting on a network send. Sends still need
///     the API; offline-send queue is a separate, larger feature.
///   - Cross-device delete / edit reconciliation while offline. If a
///     row was deleted on another device while this one was offline,
///     the local cache will show it stale until the next realtime
///     `message_deleted` event or refresh.
enum ChatCache {
    /// Recent-messages cap per conversation. Tuned for "most useful
    /// recent context fits in memory cheaply, older history is one
    /// `loadOlder` away from the API".
    private static let cap = 100

    /// Serial background queue for writes — every `messages` mutation
    /// triggers a save, and serializing prevents file corruption from
    /// concurrent writes during fast bursts (e.g. realtime arrivals).
    private static let writeQueue = DispatchQueue(label: "chat.cache.write", qos: .utility)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()
    private static let decoder = JSONDecoder()

    private static var cacheDir: URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true) else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("ChatCache", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func file(for friendshipId: UUID) -> URL? {
        cacheDir?.appendingPathComponent("\(friendshipId.uuidString.lowercased()).json")
    }

    /// Synchronous read. Called from the view model's init so the first
    /// SwiftUI render shows cached messages with no flash of empty.
    /// Decode failures (schema drift, corrupt file) fall back to [].
    static func load(friendshipId: UUID) -> [FriendMessage] {
        guard let url = file(for: friendshipId),
              let data = try? Data(contentsOf: url),
              let messages = try? decoder.decode([FriendMessage].self, from: data) else {
            return []
        }
        return messages
    }

    /// Fire-and-forget save. Trims to the most recent `cap` by `sentAt`
    /// before writing so a chatty thread doesn't grow without bound.
    /// Caller doesn't await — saves happen on a background queue.
    static func save(friendshipId: UUID, messages: [FriendMessage]) {
        let trimmed = trim(messages)
        writeQueue.async {
            guard let url = file(for: friendshipId) else { return }
            do {
                let data = try encoder.encode(trimmed)
                try data.write(to: url, options: .atomic)
            } catch {
                // Cache failures are silent — they shouldn't surface to
                // the user. The next mutation will retry.
            }
        }
    }

    static func clear(friendshipId: UUID) {
        guard let url = file(for: friendshipId) else { return }
        writeQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Wipe every cached thread. Intended for sign-out / account switch.
    static func clearAll() {
        guard let dir = cacheDir else { return }
        writeQueue.async {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private static func trim(_ messages: [FriendMessage]) -> [FriendMessage] {
        guard messages.count > cap else { return messages }
        // Sort defensively before trimming — the in-memory array is
        // generally already ordered, but a realtime arrival appended
        // before sort can briefly throw it off.
        let sorted = messages.sorted { $0.sentAt < $1.sentAt }
        return Array(sorted.suffix(cap))
    }
}
