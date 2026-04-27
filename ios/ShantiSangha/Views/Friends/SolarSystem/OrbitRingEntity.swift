import RealityKit
import SwiftUI
import UIKit
import simd

/// A faint orbit-path guide drawn as a thin annulus (a flat ring)
/// matching the planet trajectory for a given `SacredRing`. iOS
/// RealityKit doesn't ship a torus generator, so we build the mesh
/// vertex-by-vertex using the same `PlanetEntity.orbitPosition`
/// formula the planets follow — guaranteeing the guide aligns with
/// the actual orbit even with the per-ring inclination tilt.
@MainActor
final class OrbitRingEntity: Entity {
    required init() {
        super.init()
    }

    convenience init(ring: SacredRing) {
        self.init()
        guard let mesh = Self.makeMesh(for: ring) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 0.16))
        material.blending = .transparent(opacity: 0.16)
        material.faceCulling = .none
        components.set(ModelComponent(mesh: mesh, materials: [material]))
    }

    /// Builds a thin double-banded annulus that traces the orbit. Two
    /// vertex circles (outer + inner radii), 96 segments around,
    /// connected as quads → triangles. The vertices use the same
    /// inclination math as the planets so the guide matches the
    /// planet path even when the ring is tilted.
    private static func makeMesh(for ring: SacredRing, segments: Int = 96) -> MeshResource? {
        let baseRadius = ring.orbitRadius
        let thickness: Float = 0.006
        let tilt = ring.inclination

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(segments * 2)

        for i in 0..<segments {
            let angle = (Float(i) / Float(segments)) * (.pi * 2)
            for radius in [baseRadius + thickness, baseRadius - thickness] {
                let x = radius * cos(angle)
                let zFlat = radius * sin(angle)
                let y = zFlat * sin(tilt)
                let z = zFlat * cos(tilt)
                positions.append(SIMD3<Float>(x, y, z))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(segments * 6)
        for i in 0..<segments {
            let outer = UInt32(i * 2)
            let inner = UInt32(i * 2 + 1)
            let nextOuter = UInt32(((i + 1) % segments) * 2)
            let nextInner = UInt32(((i + 1) % segments) * 2 + 1)

            indices.append(outer)
            indices.append(inner)
            indices.append(nextInner)

            indices.append(outer)
            indices.append(nextInner)
            indices.append(nextOuter)
        }

        var descriptor = MeshDescriptor(name: "OrbitRing-\(ring.rawValue)")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }
}
