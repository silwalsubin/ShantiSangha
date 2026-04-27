import RealityKit
import SwiftUI
import UIKit
import simd

/// One planet — one connection. Phase 2 gives each ring a distinct
/// `PhysicallyBasedMaterial` with a procedural surface texture so
/// the closeness hierarchy reads materially. Phase 3 adds an
/// `OrbitalComponent` so the `OrbitSystem` drives the planet's
/// position + spin every frame.
@MainActor
final class PlanetEntity: Entity {
    var connectionId: UUID = UUID()
    var ring: SacredRing = .outer

    required init() {
        super.init()
    }

    convenience init(connection: Connection, ring: SacredRing, angle: Float) {
        self.init()
        self.connectionId = connection.id
        self.ring = ring
        self.name = connection.id.uuidString

        let mesh = MeshResource.generateSphere(radius: ring.planetRadius)
        let recency = Self.recencyFactor(for: connection)
        let material = Self.material(for: ring, recency: recency)
        components.set(ModelComponent(mesh: mesh, materials: [material]))

        // Phase 6 — make the planet hit-testable for SpatialTapGesture.
        // CollisionComponent provides the ray-cast shape; the
        // InputTargetComponent marks the entity as a valid tap target.
        components.set(CollisionComponent(
            shapes: [.generateSphere(radius: ring.planetRadius)]))
        components.set(InputTargetComponent())

        // Compute the initial axial tilt — stable per connection so
        // the same person always orbits with the same orientation.
        let tilt = Self.deterministicTilt(for: connection.id)
        let initialOrientation = simd_quatf(angle: tilt, axis: SIMD3<Float>(0, 0, 1))

        // Attach orbital state. The OrbitSystem will overwrite
        // `position` and `orientation` every frame using these inputs
        // — so the explicit `position` set below is just the first
        // paint before the system fires.
        let orbital = OrbitalComponent(
            ring: ring,
            baseAngle: angle,
            angularSpeed: ring.angularSpeed,
            spinSpeed: Self.deterministicSpinSpeed(for: connection.id),
            initialOrientation: initialOrientation)
        components.set(orbital)

        position = Self.orbitPosition(ring: ring, angle: angle)
        orientation = initialOrientation

        // Attach the connection's avatar as an orbiting moon. Moon
        // creation kicks off async avatar download internally — the
        // first paint shows an initial-glyph fallback.
        let moon = AvatarMoonEntity(connection: connection, planetRadius: ring.planetRadius)
        addChild(moon)

        // Atmosphere halo — billboard ring around the silhouette,
        // tinted per ring to suggest scattering. Adds the "body
        // with atmosphere" read that procedural surfaces alone miss.
        if let atmosphere = Self.makeAtmosphere(ring: ring) {
            addChild(atmosphere)
        }

        // Async-load the bundled CC4.0 planet texture and swap it
        // into the diffuse channel when ready. Falls back to the
        // procedural noise texture set above if the bundle resource
        // is missing.
        Task { [weak self] in
            guard let self else { return }
            let textureName = Self.bundledTextureName(for: ring)
            if let texture = await BundledPlanetTextures.shared.load(textureName) {
                self.applyDiffuseTexture(texture)
            }
        }
    }

    private static func bundledTextureName(for ring: SacredRing) -> String {
        switch ring {
        case .inner:  return "earth"     // family — the "us" planet
        case .middle: return "mars"      // close — warm rocky companion
        case .outer:  return "neptune"   // broader — cool distant body
        }
    }

    private func applyDiffuseTexture(_ texture: TextureResource) {
        guard var model = components[ModelComponent.self],
              let pbr = model.materials.first as? PhysicallyBasedMaterial
        else { return }
        var updated = pbr
        updated.baseColor = .init(tint: .white, texture: .init(texture))
        model.materials = [updated]
        components.set(model)
    }

    /// Billboard quad with the atmospheric ring gradient, sized just
    /// past the planet's silhouette. Tint per ring suggests
    /// scattering — warm dust for inner, golden for middle, cool blue
    /// for outer — same compositional logic Earth-from-orbit
    /// photography uses.
    private static func makeAtmosphere(ring: SacredRing) -> Entity? {
        guard let texture = PlanetTextures.atmosphereRing(size: 512) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: atmosphereTint(for: ring), texture: .init(texture))
        material.blending = .transparent(opacity: 0.65)
        material.faceCulling = .none

        let size = ring.planetRadius * 3.4
        let mesh = MeshResource.generatePlane(width: size, height: size)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.components.set(BillboardComponent())
        return entity
    }

    private static func atmosphereTint(for ring: SacredRing) -> UIColor {
        switch ring {
        case .inner:
            // Earth-like cool blue scattering
            return UIColor(red: 0.55, green: 0.78, blue: 1.00, alpha: 1.0)
        case .middle:
            // Mars-like warm dust haze
            return UIColor(red: 1.00, green: 0.65, blue: 0.40, alpha: 1.0)
        case .outer:
            // Neptune-like deep methane blue
            return UIColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 1.0)
        }
    }

    static func orbitPosition(ring: SacredRing, angle: Float) -> SIMD3<Float> {
        let r = ring.orbitRadius
        let x = r * cos(angle)
        let zFlat = r * sin(angle)
        let tilt = ring.inclination
        let y = zFlat * sin(tilt)
        let z = zFlat * cos(tilt)
        return SIMD3<Float>(x, y, z)
    }

    /// Deterministic starting angle in [0, 2π) seeded from connection
    /// id, so the same person always starts at the same baseline.
    /// Combined with the per-ring phase offset at the call site so
    /// rings don't all align.
    static func deterministicBaseAngle(for id: UUID) -> Float {
        let bytes = withUnsafeBytes(of: id.uuid) { buf -> Float in
            // Use two bytes for a 16-bit seed → ~0.0001 rad resolution
            let hi = Float(buf[0])
            let lo = Float(buf[1])
            let seed = (hi * 256 + lo) / 65535
            return seed
        }
        return bytes * (.pi * 2)
    }

    /// Per-planet axial spin in [-0.55, 0.55] rad/s. Sign is
    /// deterministic from id so ~30% of planets spin retrograde for
    /// variety, the rest prograde. Stable across launches.
    private static func deterministicSpinSpeed(for id: UUID) -> Float {
        let bytes = withUnsafeBytes(of: id.uuid) { buf -> (Float, Float) in
            (Float(buf[2]) / 255.0, Float(buf[3]) / 255.0)
        }
        let magnitude = 0.20 + bytes.0 * 0.35
        let sign: Float = bytes.1 < 0.30 ? -1 : 1
        return magnitude * sign
    }

    private static func material(for ring: SacredRing, recency: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let palette = palette(for: ring)
        let texture = PlanetTextures.generate(
            base: palette.base,
            accent: palette.accent,
            highlight: palette.highlight,
            accentBlobs: palette.accentBlobs,
            highlightBlobs: palette.highlightBlobs)

        if let texture {
            m.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            m.baseColor = .init(tint: palette.base)
        }

        switch ring {
        case .inner:
            m.metallic = 0.25
            m.roughness = 0.55
        case .middle:
            m.metallic = 0.85
            m.roughness = 0.30
        case .outer:
            m.metallic = 0.10
            m.roughness = 0.85
        }

        // Recency emissive — recently-active connections (< 48h) glow
        // strongly, fading to nothing over the 48h–30d window. Inner
        // ring keeps a small baseline ember even when inactive so the
        // family core always feels "alive."
        let baseline = ringBaseEmissive(for: ring)
        m.emissiveColor = .init(color: ringEmissiveColor(for: ring))
        m.emissiveIntensity = baseline + recency * 0.85
        return m
    }

    /// 1.0 if last message was within 48h, 0 if older than 30d, smooth
    /// linear ramp in between. Returns 0 for connections with no
    /// `lastMessageAt` (never-messaged locals).
    private static func recencyFactor(for connection: Connection) -> Float {
        guard let date = FriendsDates.parse(connection.lastMessageAt) else { return 0 }
        let hoursSince = Date().timeIntervalSince(date) / 3600.0
        if hoursSince <= 48 { return 1.0 }
        if hoursSince > 720 { return 0 }
        let t = (hoursSince - 48) / (720 - 48)
        return Float(max(0, 1.0 - t))
    }

    /// Per-ring baseline emissive intensity (no-recency floor). Inner
    /// ring has a small always-on ember so family planets read as
    /// warm even when nothing's recent; middle/outer go dark.
    private static func ringBaseEmissive(for ring: SacredRing) -> Float {
        switch ring {
        case .inner:  return 0.15
        case .middle: return 0.0
        case .outer:  return 0.0
        }
    }

    /// Per-ring emissive color — picked to harmonize with each ring's
    /// base palette so the recency glow feels like the planet itself
    /// brightening rather than a foreign tint.
    private static func ringEmissiveColor(for ring: SacredRing) -> UIColor {
        switch ring {
        case .inner:
            // Warm orange ember, hottest at < 48h
            return UIColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1.0)
        case .middle:
            // Pearl-gold glow matching the polished mid-ring palette
            return UIColor(red: 1.00, green: 0.85, blue: 0.55, alpha: 1.0)
        case .outer:
            // Cool ice glow — outer ring keeps its complementary hue
            return UIColor(red: 0.65, green: 0.80, blue: 1.00, alpha: 1.0)
        }
    }

    private static func palette(for ring: SacredRing) -> (
        base: UIColor, accent: UIColor, highlight: UIColor,
        accentBlobs: Int, highlightBlobs: Int
    ) {
        // Free cosmic palette (no sacred-UI constraints) — diverse hues
        // give the rendering enough contrast that planets actually read
        // as distinct bodies instead of three saffron blobs. Inner is
        // warm rocky terracotta, middle is pearl-gold, outer is cool
        // teal-violet. Each ring's accent is a darker companion of its
        // base so the procedural noise texture has visible structure.
        switch ring {
        case .inner:
            // Family — Mars-like terracotta with deep iron oxide
            // shadow bands.
            return (
                base: UIColor(red: 0.78, green: 0.42, blue: 0.28, alpha: 1.0),
                accent: UIColor(red: 0.32, green: 0.12, blue: 0.06, alpha: 1.0),
                highlight: UIColor(red: 1.00, green: 0.75, blue: 0.55, alpha: 1.0),
                accentBlobs: 280,
                highlightBlobs: 110)
        case .middle:
            // Close — Venus-like pearl with warm cream undertones and
            // hot specular glints. Catches the sun cleanly.
            return (
                base: UIColor(red: 0.92, green: 0.84, blue: 0.70, alpha: 1.0),
                accent: UIColor(red: 0.55, green: 0.40, blue: 0.20, alpha: 1.0),
                highlight: UIColor(red: 1.00, green: 0.96, blue: 0.85, alpha: 1.0),
                accentBlobs: 160,
                highlightBlobs: 140)
        case .outer:
            // Broader — Neptune-like deep teal/violet ice. Cool tones
            // give the scene complementary contrast against the warm
            // sun and inner rings.
            return (
                base: UIColor(red: 0.30, green: 0.40, blue: 0.62, alpha: 1.0),
                accent: UIColor(red: 0.10, green: 0.12, blue: 0.28, alpha: 1.0),
                highlight: UIColor(red: 0.65, green: 0.78, blue: 0.95, alpha: 1.0),
                accentBlobs: 200,
                highlightBlobs: 70)
        }
    }

    private static func deterministicTilt(for id: UUID) -> Float {
        let byte = withUnsafeBytes(of: id.uuid) { Float($0[0]) / 255.0 }
        return (byte - 0.5) * 0.7
    }
}
