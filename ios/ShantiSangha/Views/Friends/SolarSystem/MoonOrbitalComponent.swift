import RealityKit

/// Per-moon orbital state. Moons are children of their planet, so
/// position is stored in *local* space (relative to parent) and the
/// `OrbitSystem` writes only the moon's local transform — RealityKit
/// composes with the planet's world transform automatically.
struct MoonOrbitalComponent: Component {
    var orbitRadius: Float       // distance from parent planet's center
    var angularSpeed: Float      // rad/s
    var baseAngle: Float         // initial offset, deterministic per connection
    var inclination: Float       // small tilt of the moon's orbit plane
}
