import RealityKit
import SolarSystemAssets

/// Loads RCP-authored `ShaderGraphMaterial`s from the
/// `SolarSystemAssets` package bundle. Returns nil on any failure
/// (asset missing during dev iterations, material renamed mid-edit,
/// build cache stale, etc.) so callers fall back gracefully to the
/// procedural pipeline rather than crashing or showing a placeholder.
@MainActor
enum MaterialLoader {
    /// Async-load a shader graph material by prim path + scene file.
    ///   - primPath: USD-style path to the material prim, e.g.
    ///     `"/Root/Material"`
    ///   - sceneFile: Filename of the .usda inside the .rkassets,
    ///     without the extension (e.g. `"SunCoronaMaterial"`).
    static func shaderGraph(
        named primPath: String,
        from sceneFile: String
    ) async -> ShaderGraphMaterial? {
        do {
            return try await ShaderGraphMaterial(
                named: primPath,
                from: sceneFile,
                in: SolarSystemAssets.bundle)
        } catch {
            print("MaterialLoader: failed \(sceneFile)\(primPath) — \(error)")
            return nil
        }
    }
}
