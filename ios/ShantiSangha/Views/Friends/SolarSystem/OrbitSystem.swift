import RealityKit
import QuartzCore
import simd

/// RealityKit `System` that drives orbital motion + axial spin for
/// every entity carrying an `OrbitalComponent` (planets) or a
/// `MoonOrbitalComponent` (avatar moons). Reads
/// `CACurrentMediaTime()` directly rather than accumulating delta-time
/// — this makes positions deterministic across rebuilds (refresh,
/// SwiftUI re-render) and across the system's own re-creation.
///
/// Honors `MotionPreferences.reduceMotion`: when true, every entity
/// is frozen at its `baseAngle` (no time-driven motion). Recency
/// emissive, lighting, and the scene itself still render — only the
/// orbital animation pauses.
final class OrbitSystem: System {
    private static let planetQuery = EntityQuery(where: .has(OrbitalComponent.self))
    private static let moonQuery = EntityQuery(where: .has(MoonOrbitalComponent.self))

    required init(scene: Scene) {}

    @MainActor
    func update(context: SceneUpdateContext) {
        let reduceMotion = MotionPreferences.reduceMotion
        // Keep the multiplication in Double — `CACurrentMediaTime()`
        // returns seconds-since-boot, which after a long uptime
        // overflows Float precision for trig. Reduce modulo 2π in
        // Double, *then* cast — the resulting angle is in (-2π, 2π)
        // exactly so cos/sin are precise regardless of uptime.
        let t = reduceMotion ? 0.0 : CACurrentMediaTime()
        let twoPi = Double.pi * 2

        for entity in context.scene.performQuery(Self.planetQuery) {
            guard let orbital = entity.components[OrbitalComponent.self] else { continue }

            let orbitalAngle = (Double(orbital.baseAngle) + t * Double(orbital.angularSpeed))
                .truncatingRemainder(dividingBy: twoPi)
            entity.position = PlanetEntity.orbitPosition(
                ring: orbital.ring,
                angle: Float(orbitalAngle))

            let spinAngle = (t * Double(orbital.spinSpeed))
                .truncatingRemainder(dividingBy: twoPi)
            let spin = simd_quatf(angle: Float(spinAngle), axis: SIMD3<Float>(0, 1, 0))
            entity.orientation = orbital.initialOrientation * spin
        }

        // Moons are children of their planet — we set local position
        // here; RealityKit composes with the parent's world transform
        // automatically. `BillboardComponent` on the moon overrides
        // orientation, so we don't write that.
        for entity in context.scene.performQuery(Self.moonQuery) {
            guard let orbital = entity.components[MoonOrbitalComponent.self] else { continue }
            let angle = Float((Double(orbital.baseAngle) + t * Double(orbital.angularSpeed))
                .truncatingRemainder(dividingBy: twoPi))
            entity.position = AvatarMoonEntity.localPosition(orbital: orbital, angle: angle)
        }
    }
}
