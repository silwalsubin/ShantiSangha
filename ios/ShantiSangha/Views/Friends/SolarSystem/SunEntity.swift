import RealityKit
import SwiftUI
import UIKit

/// The user's "sun" at the center of the circle.
///
/// Bright core + smooth multi-shell halo. The core async-loads a
/// real solar-surface texture (CC BY 4.0 from solarsystemscope.com)
/// for surface detail; falls back to a flat warm-white tint until
/// the texture decodes.
@MainActor
final class SunEntity: Entity {
    private static let coreRadius: Float = 0.36
    private static let haloSize: Float = 2.6
    private static let haloTint = UIColor(red: 1.00, green: 0.65, blue: 0.25, alpha: 1.0)
    private static let coreTint = UIColor(red: 1.00, green: 0.92, blue: 0.78, alpha: 1.0)

    private let core: ModelEntity

    required init() {
        // Core is a stored property so the async texture-swap can
        // find it without walking the children list.
        self.core = SunEntity.makeCore()
        super.init()
        addChild(core)
        if let halo = makeHalo() {
            addChild(halo)
        }
        components.set(makeKeyLight())

        // Async-load the real sun texture and swap it in when ready.
        // No-op if the bundle resource is missing.
        Task { [weak self] in
            if let texture = await BundledPlanetTextures.shared.load("sun") {
                self?.applyCoreTexture(texture)
            }
        }

        // RCP `SunCoronaMaterial` load is intentionally disabled —
        // the bundled sun.jpg texture already gives a strong "real
        // solar surface" look, and a procedural shader graph can't
        // beat that without significant authoring (Fresnel + noise
        // + animated UV scroll, which is a multi-iteration RCP job).
        // The MaterialLoader / package infrastructure stays in place
        // so future RCP work (planet atmospheric Fresnel, etc.)
        // doesn't need to re-do setup. To re-enable: uncomment.
        //
        // Task { [weak self] in
        //     if let material = await MaterialLoader.shaderGraph(
        //         named: "/Root/Material",
        //         from: "SunCoronaMaterial")
        //     {
        //         self?.applyCoreShaderGraph(material)
        //     }
        // }
    }

    private static func makeCore() -> ModelEntity {
        let material = UnlitMaterial(color: Self.coreTint)
        let mesh = MeshResource.generateSphere(radius: Self.coreRadius)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private func applyCoreTexture(_ texture: TextureResource) {
        var material = UnlitMaterial(color: .white)
        material.color = .init(tint: .white, texture: .init(texture))
        if var model = core.model {
            model.materials = [material]
            core.model = model
        }
    }

    private func applyCoreShaderGraph(_ material: ShaderGraphMaterial) {
        if var model = core.model {
            model.materials = [material]
            core.model = model
        }
    }

    /// Billboard quad with a radial-gradient alpha texture, tinted
    /// to the warm halo color. `BillboardComponent` keeps the quad
    /// facing the camera so the halo always reads as a circular
    /// glow rather than a foreshortened ellipse.
    private func makeHalo() -> Entity? {
        guard let texture = PlanetTextures.radialGradient(size: 1024) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: Self.haloTint, texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none

        let mesh = MeshResource.generatePlane(width: Self.haloSize, height: Self.haloSize)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.components.set(BillboardComponent())
        return entity
    }

    private func makeKeyLight() -> PointLightComponent {
        PointLightComponent(
            color: Self.haloTint,
            intensity: 90_000,
            attenuationRadius: 12.0)
    }
}
