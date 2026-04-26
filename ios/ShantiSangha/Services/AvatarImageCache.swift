import Foundation
import UIKit

/// In-memory shared cache of remote avatar images, keyed by URL.
///
/// AsyncImage doesn't deduplicate concurrent requests for the same URL,
/// so a chat scroll with five "first-of-run" friend bubbles fires five
/// independent fetches. Some win the race and render the photo; others
/// fall into `.failure` from network jitter or transient 4xx and never
/// retry — which is why the 12pt read-receipt avatar might show the
/// photo while the 28pt gutter avatar of the same friend shows the
/// fallback person icon.
///
/// `image(for:)` dedupes via an in-flight task table and stores the
/// decoded UIImage in NSCache. Subsequent SacredAvatar instances for
/// the same URL render from the cached image instantly with no network
/// call.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    /// Pixel-budget for cached images. NSCache evicts on memory pressure
    /// regardless, so this is a soft ceiling — enough to hold a few
    /// dozen avatars at full resolution.
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 100
        return c
    }()

    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    /// Returns the cached UIImage for `url`, or fetches it once and
    /// caches the result. Concurrent callers for the same URL await
    /// the same in-flight task — one network request per URL.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        let nsKey = key as NSString

        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let img = UIImage(data: data) else {
                    return nil
                }
                self?.cache.setObject(img, forKey: nsKey)
                return img
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        return result
    }
}
