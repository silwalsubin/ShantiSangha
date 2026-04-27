import RealityKit

/// Drives a sin-based scale pulse on its host entity. Used by the
/// unread-message halo around avatar moons — the gentle scale wobble
/// reads as "there's something here for you" without being
/// notification-red alarming.
///
/// `phaseOffset` is per-entity so different moons don't pulse in
/// lockstep (one synchronized blink would feel mechanical; offset
/// pulses feel like a living constellation).
struct PulseComponent: Component {
    var period: Float        // seconds for a full sin cycle
    var minScale: Float
    var maxScale: Float
    var phaseOffset: Float   // seconds, deterministic per-entity
}
