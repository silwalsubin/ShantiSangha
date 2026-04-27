import RealityKit
import UIKit
import Foundation

/// Async-loads avatar URLs into `TextureResource`s with caching and
/// in-flight coalescing — multiple planets requesting the same avatar
/// (rare but possible if a person appears on multiple rings via custom
/// relationships) share one network round-trip and one decode.
///
/// Main-actor isolated, so the cache + inflight dictionaries don't
/// need locking. The actual URLSession download still runs off the
/// main thread (URLSession's nature) — only the dispatch is serialized.
@MainActor
final class AvatarTextureLoader {
    static let shared = AvatarTextureLoader()

    private let cache = NSCache<NSString, TextureResource>()
    private var inflight: [String: Task<TextureResource?, Never>] = [:]

    private init() {
        // Avatar textures are 256×256 — keep ~50 in memory.
        cache.countLimit = 64
    }

    func loadTexture(from urlString: String) async -> TextureResource? {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let inflightTask = inflight[urlString] {
            return await inflightTask.value
        }

        let task = Task<TextureResource?, Never> { [weak self] in
            guard let url = URL(string: urlString) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let uiImage = UIImage(data: data),
                      let cg = uiImage.cgImage
                else { return nil }
                let texture = try await TextureResource(
                    image: cg,
                    options: TextureResource.CreateOptions(semantic: .color))
                self?.cache.setObject(texture, forKey: urlString as NSString)
                return texture
            } catch {
                return nil
            }
        }

        inflight[urlString] = task
        let result = await task.value
        inflight.removeValue(forKey: urlString)
        return result
    }
}
