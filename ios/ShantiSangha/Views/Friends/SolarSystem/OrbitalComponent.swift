import RealityKit
import simd

/// Per-planet orbital state. Position and orientation are recomputed
/// every frame from absolute wall-clock time, so rebuilds (refresh,
/// connection list change) don't snap the planets back to start —
/// they pick up at the angle where they "should be" right now.
struct OrbitalComponent: Component {
    var ring: SacredRing
    /// Stable starting offset, derived from connection.id so the same
    /// person always orbits from the same baseline.
    var baseAngle: Float
    /// Radians per second. Inner rings spin faster (Kepler-ish).
    var angularSpeed: Float
    /// Per-planet axial spin rate, signed (negative = retrograde).
    var spinSpeed: Float
    /// Stable axial tilt + initial yaw applied before the spin.
    var initialOrientation: simd_quatf
}
