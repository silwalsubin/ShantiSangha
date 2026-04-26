import Foundation

/// On-disk cache for chat-message media binaries (images + voice).
/// One file per message id under `Application Support/ChatMedia/`.
///
/// Why cache by message id rather than URL: backend mediaUrls are
/// presigned S3 links with a TTL — the URL itself rotates on every
/// API fetch, but the underlying binary doesn't. Keying on the
/// stable message id means we download once and reuse forever.
///
/// Capacity is enforced lazily on write: when a new file would push
/// the directory over `capacityBytes`, the oldest-accessed files are
/// evicted until the new write fits.
actor ChatMediaCache {
    static let shared = ChatMediaCache()

    /// Total disk budget for media. ~100MB feels right for a chat-
    /// only feature that's not the user's primary photo store; if
    /// a user backs up via iCloud they'll never miss a stale chat
    /// photo, and the per-message redownload is cheap.
    private let capacityBytes: Int64 = 100 * 1024 * 1024

    private let dir: URL?
    /// In-flight downloads, keyed by message id, so two near-simultaneous
    /// renders of the same bubble don't kick off duplicate fetches.
    private var inFlight: [UUID: Task<URL?, Never>] = [:]

    init() {
        let fm = FileManager.default
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true) {
            let target = appSupport.appendingPathComponent("ChatMedia", isDirectory: true)
            if !fm.fileExists(atPath: target.path) {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
            }
            self.dir = target
        } else {
            self.dir = nil
        }
    }

    /// Returns a `file://` URL for the message's media, downloading
    /// from `remoteUrl` on cache miss. Returns nil if the directory
    /// is unavailable or the download fails — callers should fall
    /// back to the remote URL in that case.
    func cachedURL(messageId: UUID, remoteUrl: URL) async -> URL? {
        guard let dir else { return nil }
        let local = dir.appendingPathComponent(messageId.uuidString.lowercased())

        // Hit: touch atime so LRU eviction sees this file as recently
        // used, then return the local URL.
        if FileManager.default.fileExists(atPath: local.path) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: local.path)
            return local
        }

        // Miss: coalesce concurrent fetches.
        if let existing = inFlight[messageId] {
            return await existing.value
        }
        let task = Task<URL?, Never> { [weak self] in
            guard let self else { return nil }
            let result = await self.download(remoteUrl, to: local)
            await self.clearInFlight(messageId)
            return result
        }
        inFlight[messageId] = task
        return await task.value
    }

    /// Drop a cached file — call this on `message_deleted` events so
    /// the binary doesn't outlive the row.
    func purge(messageId: UUID) {
        guard let dir else { return }
        let local = dir.appendingPathComponent(messageId.uuidString.lowercased())
        try? FileManager.default.removeItem(at: local)
    }

    /// Wipe everything. Intended for sign-out / account switch.
    func clearAll() {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func clearInFlight(_ id: UUID) {
        inFlight.removeValue(forKey: id)
    }

    private func download(_ url: URL, to local: URL) async -> URL? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }
            evictIfNeeded(toFit: Int64(data.count))
            try data.write(to: local, options: .atomic)
            return local
        } catch {
            return nil
        }
    }

    /// LRU eviction by mtime — the cheapest "least recently accessed"
    /// proxy on iOS without filesystem extended attributes. We touch
    /// mtime on every read (above), so it tracks usage well enough.
    private func evictIfNeeded(toFit incoming: Int64) {
        guard let dir else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles) else {
            return
        }

        var totalBytes: Int64 = 0
        var withMeta: [(URL, Int64, Date)] = []
        for url in entries {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? .distantPast
            totalBytes += size
            withMeta.append((url, size, date))
        }

        guard totalBytes + incoming > capacityBytes else { return }

        // Oldest first — evict until there's room for the incoming write.
        let sorted = withMeta.sorted { $0.2 < $1.2 }
        var freed: Int64 = 0
        for (url, size, _) in sorted {
            try? fm.removeItem(at: url)
            freed += size
            if totalBytes + incoming - freed <= capacityBytes { break }
        }
    }
}
