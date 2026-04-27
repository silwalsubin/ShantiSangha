import RealityKit
import SwiftUI
import UIKit
import simd

/// Owns the RealityKit entity graph for the Circle solar view.
/// Idempotent rebuild on connection changes — the SwiftUI view
/// re-invokes `setConnections` whenever its input array changes.
@MainActor
final class SolarSystemScene {
    let root: Entity
    let sun: SunEntity
    let camera: Entity
    /// Inverted UnlitMaterial sphere that wraps the camera. iOS 26
    /// `RealityViewEnvironment` no longer exposes a background color
    /// or skybox — the only way to control what the camera "sees" past
    /// our scene is to put a giant dome of our chosen color around it.
    /// Doubles as the canvas for Phase 7's starfield texture.
    private let skyDome: ModelEntity
    private(set) var planets: [PlanetEntity] = []
    private var orbitRings: [OrbitRingEntity] = []

    init() {
        // Phase 3/4/5 — register all orbital + pulse components and
        // their systems once. Registration is idempotent on iOS 18+,
        // so re-creating a scene doesn't double-register.
        OrbitalComponent.registerComponent()
        MoonOrbitalComponent.registerComponent()
        PulseComponent.registerComponent()
        OrbitSystem.registerSystem()
        PulseSystem.registerSystem()

        self.root = Entity()
        self.sun = SunEntity()
        self.camera = SolarSystemScene.makeCamera()
        self.skyDome = SolarSystemScene.makeSkyDome()
        root.addChild(skyDome)
        root.addChild(sun)
        root.addChild(camera)
        addRimFill()
        addCoolBackLight()
        addOrbitRings()
        applyStarfield()
    }

    /// Phase 7 — swap the dome's solid-black material for a
    /// procedurally-generated 4K starfield + nebula texture. If
    /// generation fails (CoreGraphics edge case), the dome stays
    /// black; the rest of the scene still renders.
    private func applyStarfield() {
        guard let texture = StarfieldTexture.generate() else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .none
        skyDome.model?.materials = [material]
    }

    /// Diff-and-replace planets. Phase 1 keeps it simple — wipe and
    /// rebuild — because a few hundred entity allocations per refresh
    /// is well within budget. Initial angles are seeded deterministically
    /// from the connection id so a refresh doesn't snap the system
    /// into a different layout.
    func setConnections(_ connections: [Connection]) {
        for planet in planets { planet.removeFromParent() }
        planets.removeAll()

        let buckets = RingAssignment.bucket(connections)
        for ring in SacredRing.allCases {
            let conns = buckets[ring] ?? []
            guard !conns.isEmpty else { continue }
            // Phase offset per ring keeps planets from stacking into
            // a single column when each ring has only one entry.
            let phase = Float(ring.rawValue) * (.pi / 4)
            for conn in conns {
                let baseAngle = phase + PlanetEntity.deterministicBaseAngle(for: conn.id)
                let planet = PlanetEntity(connection: conn, ring: ring, angle: baseAngle)
                root.addChild(planet)
                planets.append(planet)
            }
        }
    }

    /// Update the dome's tint so light/dark mode switches keep the
    /// view visually flush with the surrounding `SacredBackground`.
    func setBackgroundColor(_ uiColor: UIColor) {
        var material = UnlitMaterial(color: uiColor)
        material.faceCulling = .none
        skyDome.model?.materials = [material]
    }

    /// Phase 6 — drive the camera from gesture state. Camera sits on
    /// a sphere of radius `distance` around the origin, with
    /// `azimuth` rotating around Y and `elevation` tilting up/down.
    /// Caller is responsible for clamping inputs.
    func applyCameraState(azimuth: Float, elevation: Float, distance: Float) {
        let cosE = cos(elevation)
        let sinE = sin(elevation)
        let x = distance * cosE * sin(azimuth)
        let y = distance * sinE
        let z = distance * cosE * cos(azimuth)
        let position = SIMD3<Float>(x, y, z)
        camera.position = position
        camera.look(at: .zero, from: position, relativeTo: nil)
    }

    private func addOrbitRings() {
        for ring in SacredRing.allCases {
            let entity = OrbitRingEntity(ring: ring)
            orbitRings.append(entity)
            root.addChild(entity)
        }
    }

    private static func makeCamera() -> Entity {
        let cam = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = 65
        cam.components.set(component)
        let position = SIMD3<Float>(0, 0.55, 3.9)
        cam.position = position
        cam.look(at: .zero, from: position, relativeTo: nil)
        return cam
    }

    private static func makeSkyDome() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 500)
        var material = UnlitMaterial(color: .black)
        material.faceCulling = .none
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.scale = SIMD3<Float>(-1, 1, 1)
        return entity
    }

    private func addRimFill() {
        let entity = Entity()
        let warm = UIColor(Color.sacredGoldLight)
        entity.components.set(DirectionalLightComponent(
            color: warm,
            intensity: 1_400))
        entity.look(
            at: .zero,
            from: SIMD3<Float>(0.6, 2.0, 3.5),
            relativeTo: nil)
        root.addChild(entity)
    }

    private func addCoolBackLight() {
        let entity = Entity()
        let cool = UIColor(red: 0.32, green: 0.30, blue: 0.46, alpha: 1.0)
        entity.components.set(DirectionalLightComponent(
            color: cool,
            intensity: 850))
        entity.look(
            at: .zero,
            from: SIMD3<Float>(-1.5, -0.5, -2.5),
            relativeTo: nil)
        root.addChild(entity)
    }
}
