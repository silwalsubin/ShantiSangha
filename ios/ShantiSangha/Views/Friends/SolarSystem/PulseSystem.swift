import RealityKit
import QuartzCore

/// Drives `PulseComponent`-tagged entities. Sin-based scale pulse
/// every frame, with per-entity phase offset so multiple pulses don't
/// blink in lockstep. Honors `MotionPreferences.reduceMotion` — when
/// true, all pulses freeze at scale 1.0.
final class PulseSystem: System {
    private static let query = EntityQuery(where: .has(PulseComponent.self))

    required init(scene: Scene) {}

    @MainActor
    func update(context: SceneUpdateContext) {
        if MotionPreferences.reduceMotion {
            for entity in context.scene.performQuery(Self.query) {
                entity.scale = SIMD3<Float>(1.0, 1.0, 1.0)
            }
            return
        }

        let t = CACurrentMediaTime()
        for entity in context.scene.performQuery(Self.query) {
            guard let pulse = entity.components[PulseComponent.self] else { continue }
            let period = Double(pulse.period)
            guard period > 0.001 else { continue }
            let phase = sin((t + Double(pulse.phaseOffset)) * .pi * 2 / period) * 0.5 + 0.5
            let scale = pulse.minScale + Float(phase) * (pulse.maxScale - pulse.minScale)
            entity.scale = SIMD3<Float>(scale, scale, scale)
        }
    }
}
