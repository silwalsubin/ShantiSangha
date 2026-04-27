import RealityKit
import SwiftUI
import UIKit
import simd

/// Small avatar-textured sphere orbiting its parent planet. Always
/// faces the camera via `BillboardComponent`, so the avatar's "front"
/// (texture UV center) maps onto the side the user sees regardless
/// of where the moon is in its orbit.
///
/// Loads the avatar texture asynchronously — first paint shows the
/// initial-glyph fallback, then swaps in the downloaded avatar when
/// it arrives. No flash or layout shift; the moon just becomes the
/// person.
@MainActor
final class AvatarMoonEntity: Entity {
    var connectionId: UUID = UUID()

    required init() {
        super.init()
    }

    convenience init(connection: Connection, planetRadius: Float) {
        self.init()
        self.connectionId = connection.id

        // Smaller (0.40×) and orbiting further out (3.0×) than the
        // original sizing — lets the planet stay the dominant body
        // while the moon reads as a clear avatar-bearing satellite.
        let moonRadius = planetRadius * 0.40
        let mesh = MeshResource.generateSphere(radius: moonRadius)

        // Start with the fallback so the first paint shows something
        // recognizable even before the network round-trip resolves.
        let initial = Self.firstInitial(of: connection.displayLabel)
        let fallback = AvatarFallbackTextures.generate(initial: initial)
        var material = UnlitMaterial()
        if let fallback {
            material.color = .init(tint: .white, texture: .init(fallback))
        } else {
            material.color = .init(tint: UIColor(red: 0.92, green: 0.84, blue: 0.70, alpha: 1.0))
        }
        components.set(ModelComponent(mesh: mesh, materials: [material]))

        // Always camera-facing so the avatar's UV(0.5, 0.5) center
        // maps onto the visible hemisphere from any orbit position.
        components.set(BillboardComponent())

        // Phase 6 — moon is also hit-testable; tapping the avatar
        // routes to the same connection as tapping its planet.
        components.set(CollisionComponent(
            shapes: [.generateSphere(radius: moonRadius)]))
        components.set(InputTargetComponent())

        let orbital = MoonOrbitalComponent(
            orbitRadius: planetRadius * 3.0,
            angularSpeed: 1.0,
            baseAngle: Self.deterministicBaseAngle(for: connection.id),
            inclination: 0.18)
        components.set(orbital)

        // Initial position so the first frame doesn't show a moon
        // sitting at the planet's center.
        position = Self.localPosition(orbital: orbital, angle: orbital.baseAngle)

        // Async avatar load — replaces the fallback texture in place
        // when the download succeeds. Captures `self` weakly so a
        // tear-down before completion doesn't leak the entity.
        if let urlString = connection.person.avatarUrl, !urlString.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                if let texture = await AvatarTextureLoader.shared.loadTexture(from: urlString) {
                    self.applyTexture(texture)
                }
            }
        }

        // Unread halo — pulsing warm-saffron radial gradient behind
        // the moon when the connection has unread messages. Saffron
        // (not red) reads as "this person has something for you,"
        // not "alarm." Pulse phase is per-connection so multiple
        // unread halos don't blink in lockstep.
        if connection.unreadCount > 0,
           let halo = Self.makeUnreadHalo(moonRadius: moonRadius, connectionId: connection.id) {
            addChild(halo)
        }
    }

    private static func makeUnreadHalo(moonRadius: Float, connectionId: UUID) -> Entity? {
        guard let texture = PlanetTextures.radialGradient(size: 256) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(
            tint: UIColor(red: 1.00, green: 0.78, blue: 0.35, alpha: 1.0),
            texture: .init(texture))
        material.blending = .transparent(opacity: 0.55)
        material.faceCulling = .none

        let mesh = MeshResource.generatePlane(
            width: moonRadius * 4.5,
            height: moonRadius * 4.5)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.components.set(BillboardComponent())

        // Pulse params — per-connection phase offset so different
        // moons breathe out of sync.
        let phaseOffset = Self.deterministicPhaseOffset(for: connectionId)
        entity.components.set(PulseComponent(
            period: 1.6,
            minScale: 0.85,
            maxScale: 1.20,
            phaseOffset: phaseOffset))
        return entity
    }

    /// Random-but-stable phase offset in [0, 1.6) seconds derived
    /// from connection id bytes 6–7. Stable across launches so the
    /// same person's moon always pulses on the same beat.
    private static func deterministicPhaseOffset(for id: UUID) -> Float {
        let byte = withUnsafeBytes(of: id.uuid) { Float($0[6]) / 255.0 }
        return byte * 1.6
    }

    /// Local-space position relative to the parent planet. The
    /// `OrbitSystem` uses the same formula every frame.
    static func localPosition(orbital: MoonOrbitalComponent, angle: Float) -> SIMD3<Float> {
        let r = orbital.orbitRadius
        let x = r * cos(angle)
        let zFlat = r * sin(angle)
        let y = zFlat * sin(orbital.inclination)
        let z = zFlat * cos(orbital.inclination)
        return SIMD3<Float>(x, y, z)
    }

    private func applyTexture(_ texture: TextureResource) {
        guard var model = components[ModelComponent.self] else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        model.materials = [material]
        components.set(model)
    }

    private static func firstInitial(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// Stable starting angle in [0, 2π) seeded from bytes 4–5 of the
    /// connection id (planet uses bytes 0–1; using different bytes
    /// keeps planet and moon angles uncorrelated).
    private static func deterministicBaseAngle(for id: UUID) -> Float {
        let bytes = withUnsafeBytes(of: id.uuid) { buf -> Float in
            (Float(buf[4]) * 256 + Float(buf[5])) / 65535
        }
        return bytes * (.pi * 2)
    }
}
