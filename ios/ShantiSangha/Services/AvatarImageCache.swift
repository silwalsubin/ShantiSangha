import Foundation
import UIKit

/// Shared avatar image cache backed by disk.
///
/// Avatar download URLs are presigned, so their query strings rotate even
/// when the underlying S3 object has not changed. The cache identity strips
/// query + fragment and keeps `scheme://host/path`; a new avatar upload gets
/// a new object path, which naturally misses this cache and downloads once.
///
/// Bytes are stored under Application Support so avatars survive app relaunch.
/// The memory cache is only a fast mirror; disk is the source of truth.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 160
        return c
    }()

    private let fm = FileManager.default
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private lazy var dir: URL? = {
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let target = base.appendingPathComponent("AvatarImages", isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = target
        try? mutable.setResourceValues(values)
        return target
    }()

    private init() {}

    /// Returns the cached UIImage for `url`, or fetches and persists it.
    /// Concurrent callers for the same avatar await one shared fetch.
    func image(for url: URL) async -> UIImage? {
        guard let identity = Self.stableIdentity(for: url) else { return nil }
        let nsKey = identity as NSString

        if let cached = cachedImage(identity: identity, nsKey: nsKey, url: url) {
            return cached
        }
        if let existing = inFlight[identity] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }

            if let cached = self.cachedImage(identity: identity, nsKey: nsKey, url: url) {
                return cached
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    return nil
                }

                self.persist(data: data, image: image, identity: identity, nsKey: nsKey, url: url)
                return image
            } catch {
                return nil
            }
        }

        inFlight[identity] = task
        let result = await task.value
        inFlight.removeValue(forKey: identity)
        return result
    }

    func clearAll() {
        guard let dir else { return }
        memory.removeAllObjects()
        inFlight.removeAll()
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func cachedImage(identity: String, nsKey: NSString, url: URL) -> UIImage? {
        if let cached = memory.object(forKey: nsKey) {
            return cached
        }

        guard let local = localURL(identity: identity, url: url),
              let data = try? Data(contentsOf: local),
              let image = UIImage(data: data) else {
            return nil
        }

        memory.setObject(image, forKey: nsKey)
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: local.path)
        return image
    }

    private func persist(data: Data, image: UIImage, identity: String, nsKey: NSString, url: URL) {
        memory.setObject(image, forKey: nsKey)
        guard let local = localURL(identity: identity, url: url) else { return }
        try? data.write(to: local, options: .atomic)
    }

    private func localURL(identity: String, url: URL) -> URL? {
        guard let dir else { return nil }
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return dir.appendingPathComponent("\(Self.fnv1a64(identity)).\(ext)")
    }

    private static func stableIdentity(for url: URL) -> String? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        if let stable = components?.url?.absoluteString, !stable.isEmpty {
            return stable
        }

        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        let path = url.path
        let fallback = "\(scheme)://\(host)\(path)"
        return fallback.isEmpty ? nil : fallback
    }

    private static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(format: "%016llx", hash)
    }
}
