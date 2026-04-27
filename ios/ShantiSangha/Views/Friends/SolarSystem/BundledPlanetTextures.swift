import RealityKit
import UIKit
import Foundation

/// Loads CC4.0-attribution planet textures from the app bundle and
/// caches them as `TextureResource`. Sources:
///   - sun.jpg, mars.jpg, neptune.jpg, earth.jpg
///   - solarsystemscope.com/textures (CC BY 4.0)
///
/// Multiple planets sharing the same ring (e.g., five inner-ring
/// connections) all share one decoded texture via the cache; in-flight
/// coalescing means only one load happens even if two planets request
/// the same texture concurrently.
@MainActor
final class BundledPlanetTextures {
    static let shared = BundledPlanetTextures()

    private var cache: [String: TextureResource] = [:]
    private var inflight: [String: Task<TextureResource?, Never>] = [:]

    private init() {}

    /// Async load by base name (no extension). Returns nil if the
    /// resource is missing or the texture pipeline rejects the image.
    /// Caller falls back to the procedural texture path.
    func load(_ name: String, ext: String = "jpg") async -> TextureResource? {
        if let cached = cache[name] { return cached }
        if let task = inflight[name] { return await task.value }

        let task = Task<TextureResource?, Never> { [weak self] in
            // Synchronized file system groups in Xcode usually
            // preserve subdirectory structure when copying resources
            // — but some build configurations flatten them, so we
            // fall back to a bare lookup as well.
            let url: URL? =
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/PlanetTextures")
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "PlanetTextures")
                ?? Bundle.main.url(forResource: name, withExtension: ext)

            guard let url,
                  let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data),
                  let cg = uiImage.cgImage
            else { return nil }

            do {
                let texture = try await TextureResource(
                    image: cg,
                    options: TextureResource.CreateOptions(semantic: .color))
                self?.cache[name] = texture
                return texture
            } catch {
                return nil
            }
        }

        inflight[name] = task
        let result = await task.value
        inflight.removeValue(forKey: name)
        return result
    }
}
