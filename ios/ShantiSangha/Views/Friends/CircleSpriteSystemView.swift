import SwiftUI
import SpriteKit
import UIKit

/// SpriteKit "circle" visualization. The user is the sun at the center,
/// each connection is a planet on one of three orbital rings (family /
/// close / broader). Fully procedural — no asset pipeline, just code.
///
/// Visual layers, back to front:
///   1. Transparent scene — the SwiftUI `SacredBackground` bleeds through
///   2. Radial nebula glow over the parchment
///   3. Far starfield (slow parallax, twinkle)
///   4. Near starfield (faster parallax)
///   5. Three orbital ring guides (faint dashed gold)
///   6. The sun — the user — multi-layered glow + corona
///   7. Planet nodes — one per connection, orbiting at ring speed
///   8. Recency embers + comet trails on planets active < 48h
///
/// Interactivity:
///   • Drag    — orbits the camera around the sun (rotate the world)
///   • Pinch   — zoom in/out
///   • Tap     — invokes onTap with the planet's connection id
///   • Double  — springs camera back to default
struct CircleSpriteSystemView: View {
    let connections: [Connection]
    /// User's profile pic — rendered at the center as the "sun." The
    /// corona glow + ember rings still run on top so the user reads
    /// as the heart of the system, not just another planet.
    let myAvatarUrl: String?
    let myDisplayName: String?
    /// Bumping this UUID from the parent triggers a camera reset
    /// (rotation + zoom + pan back to defaults). The parent owns the
    /// state so a toolbar button can fire it without reaching into
    /// the scene.
    var resetTrigger: UUID = UUID()
    let onTap: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var holder = SpriteSceneHolder()

    var body: some View {
        SpriteView(
            scene: holder.scene,
            options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes, .allowsTransparency]
        )
        .onAppear {
            holder.scene.onTap = onTap
            holder.scene.reduceMotion = reduceMotion
            holder.scene.setMe(avatarUrl: myAvatarUrl, displayName: myDisplayName)
            holder.scene.update(connections: connections)
        }
        .onChange(of: connections) { _, new in
            holder.scene.update(connections: new)
        }
        .onChange(of: reduceMotion) { _, new in
            holder.scene.reduceMotion = new
        }
        .onChange(of: myAvatarUrl) { _, _ in
            holder.scene.setMe(avatarUrl: myAvatarUrl, displayName: myDisplayName)
        }
        .onChange(of: myDisplayName) { _, _ in
            holder.scene.setMe(avatarUrl: myAvatarUrl, displayName: myDisplayName)
        }
        .onChange(of: resetTrigger) { _, _ in
            holder.scene.resetCamera()
        }
        .accessibilityRepresentation { accessibilityList }
    }

    @ViewBuilder
    private var accessibilityList: some View {
        VStack(spacing: 0) {
            Text("Solar circle visualization. \(connections.count) connections.")
                .accessibilityAddTraits(.isHeader)
            ForEach(connections) { conn in
                Button {
                    onTap(conn.id)
                } label: {
                    Text(accessibilityLabel(for: conn))
                }
                .accessibilityHint("Double tap to open chat or details")
            }
        }
    }

    private func accessibilityLabel(for connection: Connection) -> String {
        var parts: [String] = [connection.displayLabel]
        if !connection.circlesLabel.isEmpty {
            parts.append(connection.circlesLabel.lowercased())
        }
        if connection.unreadCount > 0 {
            parts.append("\(connection.unreadCount) unread")
        }
        if let date = FriendsDates.parse(connection.lastMessageAt) {
            let hours = Date().timeIntervalSince(date) / 3600
            if hours <= 48 {
                parts.append("active recently")
            } else if hours <= 720 {
                parts.append("active this month")
            }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Scene holder

/// `@State` requires its value at declaration, but SKScene wants the
/// main actor and likes to be created once and reused across redraws.
/// A small ObservableObject keeps a stable reference and dodges the
/// `@MainActor` initialization dance.
@MainActor
final class SpriteSceneHolder: ObservableObject {
    let scene: CircleSpriteScene
    init() {
        let s = CircleSpriteScene(size: CGSize(width: 400, height: 600))
        s.scaleMode = .resizeFill
        s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Transparent so the SwiftUI `SacredBackground` (warm parchment
        // + soft gold radials) bleeds through, keeping Circle visually
        // continuous with the rest of the tabs instead of floating its
        // own dark rectangle on top.
        s.backgroundColor = .clear
        self.scene = s
    }
}

// MARK: - Scene

final class CircleSpriteScene: SKScene {

    // MARK: Public surface

    var onTap: ((UUID) -> Void)?
    var reduceMotion: Bool = false {
        didSet { applyReduceMotion() }
    }

    // MARK: Layers

    private let world = SKNode()
    private let nebula = SKNode()
    private let starsFar = SKNode()
    private let starsNear = SKNode()
    private let ringGuides = SKNode()
    private let sun = SKNode()
    private let orbits: [SacredRing: SKNode] = [
        .inner: SKNode(),
        .middle: SKNode(),
        .outer: SKNode()
    ]

    // MARK: State

    private var planetSprites: [UUID: PlanetSprite] = [:]
    private var didBuild = false
    private var installedRecognizers: [UIGestureRecognizer] = []

    // Sun avatar nodes — rebuilt lazily when the user's profile arrives.
    // Stored as scene-level refs so setMe(...) can swap the texture
    // without rebuilding the whole sun stack.
    private var sunAvatarSprite: SKSpriteNode?
    private var sunInitialsLabel: SKLabelNode?
    private var pendingMyAvatarUrl: String?
    private var pendingMyDisplayName: String?
    private static let sunAvatarRadius: CGFloat = 32

    // Camera / gesture state
    private var baseScale: CGFloat = 1.0
    private var pinchScale: CGFloat = 1.0
    private let minScale: CGFloat = 0.55
    private let maxScale: CGFloat = 2.4
    private var dragAccumulated: CGVector = .zero
    private var dragSession: CGVector?
    private var defaultRotation: CGFloat { 0 }
    private var defaultPosition: CGPoint { .zero }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true

        if !didBuild {
            addChild(world)
            world.addChild(nebula)
            world.addChild(starsFar)
            world.addChild(starsNear)
            world.addChild(ringGuides)
            world.addChild(sun)
            for (_, orbit) in orbits { world.addChild(orbit) }

            buildNebula()
            buildStarfields()
            buildRingGuides()
            buildSun()
            startOrbitRotations()
            didBuild = true
        }

        // Default to the meditative half-speed baseline. Reduce Motion
        // overrides to fully frozen.
        applyReduceMotion()
        installGestures(on: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Keep nebula sized to the viewport so it always fills the frame.
        rebuildNebulaIfNeeded()
    }

    // MARK: - Build: nebula

    private func rebuildNebulaIfNeeded() {
        nebula.removeAllChildren()
        buildNebula()
    }

    private func buildNebula() {
        let radius = max(size.width, size.height) * 0.9
        // Two soft radial halos blended additively give the cosmic
        // depth without needing a Metal shader. Both stay within the
        // sacred warm palette — the original second halo was a cool
        // violet, which broke the "no cold colors" rule. Replaced
        // with `sacredGold` at lower alpha for a slightly hotter
        // accent on top of the deeper `sacredGoldDark` base halo.
        let warm = SKShapeNode(circleOfRadius: radius)
        warm.fillColor = .sacredGoldDark
        warm.strokeColor = .clear
        warm.alpha = 0.22
        warm.blendMode = .add
        warm.zPosition = -100
        nebula.addChild(warm)

        let accent = SKShapeNode(circleOfRadius: radius * 0.7)
        accent.fillColor = .sacredGold
        accent.strokeColor = .clear
        accent.alpha = 0.10
        accent.blendMode = .add
        accent.position = CGPoint(x: -radius * 0.25, y: radius * 0.18)
        accent.zPosition = -99
        nebula.addChild(accent)

        let drift = SKAction.sequence([
            .move(by: CGVector(dx: 12, dy: -8), duration: 18),
            .move(by: CGVector(dx: -12, dy: 8), duration: 18)
        ])
        accent.run(.repeatForever(drift))
    }

    // MARK: - Build: starfield

    private func buildStarfields() {
        let farTexture = Self.makeStarTexture(radius: 1.0, alpha: 0.7)
        let nearTexture = Self.makeStarTexture(radius: 1.6, alpha: 0.95)

        let radius = max(size.width, size.height) * 1.4

        for _ in 0..<240 {
            let star = SKSpriteNode(texture: farTexture)
            star.position = randomPoint(within: radius)
            star.alpha = .random(in: 0.25...0.85)
            star.zPosition = -80
            starsFar.addChild(star)
            attachTwinkle(to: star, baseAlpha: star.alpha)
        }

        for _ in 0..<70 {
            let star = SKSpriteNode(texture: nearTexture)
            star.position = randomPoint(within: radius * 0.9)
            star.alpha = .random(in: 0.6...1.0)
            star.zPosition = -70
            star.color = UIColor.sacredCosmicText
            star.colorBlendFactor = .random(in: 0.0...0.6)
            starsNear.addChild(star)
            attachTwinkle(to: star, baseAlpha: star.alpha)
        }
    }

    private func attachTwinkle(to node: SKNode, baseAlpha: CGFloat) {
        let dim = SKAction.fadeAlpha(to: max(0.1, baseAlpha * 0.4), duration: .random(in: 1.6...3.2))
        let lit = SKAction.fadeAlpha(to: baseAlpha, duration: .random(in: 1.8...3.4))
        node.run(.repeatForever(.sequence([dim, lit])))
    }

    private func randomPoint(within radius: CGFloat) -> CGPoint {
        // Uniform in disk: r = R * sqrt(u), theta = 2π * v.
        let u = CGFloat.random(in: 0...1)
        let v = CGFloat.random(in: 0...1)
        let r = radius * sqrt(u)
        let theta = 2 * .pi * v
        return CGPoint(x: r * cos(theta), y: r * sin(theta))
    }

    // MARK: - Build: ring guides

    private func buildRingGuides() {
        for ring in SacredRing.allCases {
            let radius = ringRadius(ring)
            let path = UIBezierPath(arcCenter: .zero,
                                    radius: radius,
                                    startAngle: 0,
                                    endAngle: .pi * 2,
                                    clockwise: true).cgPath
            let line = SKShapeNode(path: path)
            line.strokeColor = UIColor.sacredGold
            line.lineWidth = 0.6
            line.alpha = 0.18
            line.fillColor = .clear
            line.zPosition = -10
            ringGuides.addChild(line)
        }
    }

    // MARK: - Build: sun

    private func buildSun() {
        // Layered, back to front:
        //   1. Outer corona (additive blend, breathing)
        //   2. Mid glow halo (additive, soft)
        //   3. Avatar disc — user's profile pic, circular crop
        //   4. Gold rim around the avatar
        //   5. Initials fallback label (visible until the texture loads
        //      or when there's no avatar URL)
        //
        // The avatar IS the sun — corona/glow stay on top to keep the
        // luminous-center reading even when the photo is dim.

        let corona = SKShapeNode(circleOfRadius: 64)
        corona.fillColor = UIColor.sacredGoldShine
        corona.strokeColor = .clear
        corona.alpha = 0.10
        corona.blendMode = .add
        corona.zPosition = 4
        sun.addChild(corona)

        let glow = SKShapeNode(circleOfRadius: 42)
        glow.fillColor = UIColor.sacredGoldShine
        glow.strokeColor = .clear
        glow.alpha = 0.12
        glow.blendMode = .add
        glow.zPosition = 5
        sun.addChild(glow)

        // Avatar disc, masked to a circle.
        let r = Self.sunAvatarRadius
        let avatar = SKSpriteNode(color: UIColor.sacredCosmicBgCard,
                                  size: CGSize(width: r * 2, height: r * 2))
        avatar.zPosition = 0

        let initials = SKLabelNode(text: "")
        initials.fontName = PlanetSprite.preferredSerifFontName
        initials.fontSize = r * 0.95
        initials.fontColor = UIColor.sacredGoldShine
        initials.verticalAlignmentMode = .center
        initials.horizontalAlignmentMode = .center
        initials.zPosition = 1

        let crop = SKCropNode()
        crop.zPosition = 6
        let mask = SKShapeNode(circleOfRadius: r)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        crop.addChild(avatar)
        crop.addChild(initials)
        sun.addChild(crop)

        let rim = SKShapeNode(circleOfRadius: r)
        rim.strokeColor = UIColor.sacredGoldShine
        rim.fillColor = .clear
        rim.lineWidth = 0.6
        rim.alpha = 0.25
        rim.zPosition = 7
        sun.addChild(rim)

        sunAvatarSprite = avatar
        sunInitialsLabel = initials

        // If setMe(...) was called before didMove(to:), apply now.
        if pendingMyAvatarUrl != nil || pendingMyDisplayName != nil {
            applyMe(avatarUrl: pendingMyAvatarUrl, displayName: pendingMyDisplayName)
        }

        // Slow breath on the corona — gives the sun a heartbeat.
        let breathe = SKAction.sequence([
            .group([.scale(to: 1.10, duration: 2.6), .fadeAlpha(to: 0.16, duration: 2.6)]),
            .group([.scale(to: 1.0, duration: 2.6), .fadeAlpha(to: 0.10, duration: 2.6)])
        ])
        breathe.timingMode = .easeInEaseOut
        corona.run(.repeatForever(breathe), withKey: "breath")

        // Subtler glow pulse on the inner halo, slightly out of phase
        // with the corona so the layered glow shimmers rather than
        // expanding in lockstep.
        let glowBeat = SKAction.sequence([
            .group([.scale(to: 1.06, duration: 1.8), .fadeAlpha(to: 0.18, duration: 1.8)]),
            .group([.scale(to: 1.0, duration: 1.8), .fadeAlpha(to: 0.12, duration: 1.8)])
        ])
        glowBeat.timingMode = .easeInEaseOut
        glow.run(.repeatForever(glowBeat), withKey: "glowbeat")

        // Outward ember every ~4s — a faint pulse expanding past the
        // inner ring then dissolving. Hooks into the user's "you are
        // the heart of this circle" reading.
        spawnSunEmberLoop()
    }

    // MARK: - User avatar at the center

    func setMe(avatarUrl: String?, displayName: String?) {
        pendingMyAvatarUrl = avatarUrl
        pendingMyDisplayName = displayName
        if didBuild {
            applyMe(avatarUrl: avatarUrl, displayName: displayName)
        }
    }

    private func applyMe(avatarUrl: String?, displayName: String?) {
        let initials = Self.initials(from: displayName ?? "")
        sunInitialsLabel?.text = initials

        guard let avatarUrl, let url = URL(string: avatarUrl) else {
            sunAvatarSprite?.texture = nil
            sunAvatarSprite?.color = UIColor.sacredCosmicBgCard
            sunInitialsLabel?.alpha = 1.0
            return
        }

        // Cache by host+path, not the full URL — S3 regenerates the
        // presigned query (X-Amz-Signature, X-Amz-Date, …) on every
        // `/me` reload, which would otherwise miss the cache, refetch
        // the same image, and blink the sun blank in the meantime.
        let key = Self.avatarCacheKey(for: url)
        if let cached = PlanetSprite.avatarCache.object(forKey: key) {
            applyMyTexture(cached)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, let image = UIImage(data: data) else { return }
            PlanetSprite.avatarCache.setObject(image, forKey: key)
            DispatchQueue.main.async {
                // Compare by stable key so a presigned-URL refresh
                // mid-flight doesn't throw away a perfectly good image
                // (the path is the same, only the signature rotated).
                guard let pending = self.pendingMyAvatarUrl,
                      let pendingURL = URL(string: pending),
                      Self.avatarCacheKey(for: pendingURL) == key
                else { return }
                self.applyMyTexture(image)
            }
        }.resume()
    }

    /// Stable cache key for an avatar URL — strips the presigned query
    /// so the same underlying S3 object hits the same cache entry across
    /// `/me` reloads.
    fileprivate static func avatarCacheKey(for url: URL) -> NSString {
        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        let path = url.path
        return "\(scheme)://\(host)\(path)" as NSString
    }

    private func applyMyTexture(_ image: UIImage) {
        sunAvatarSprite?.texture = SKTexture(image: image)
        sunAvatarSprite?.color = .white
        sunAvatarSprite?.colorBlendFactor = 0
        sunInitialsLabel?.alpha = 0
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "·" : letters.uppercased()
    }

    private func spawnSunEmberLoop() {
        let spawn = SKAction.run { [weak self] in self?.spawnSunEmber() }
        let wait = SKAction.wait(forDuration: 4.2, withRange: 1.4)
        sun.run(.repeatForever(.sequence([spawn, wait])), withKey: "ember")
    }

    private func spawnSunEmber() {
        let ember = SKShapeNode(circleOfRadius: 28)
        ember.strokeColor = UIColor.sacredGoldShine
        ember.fillColor = .clear
        ember.lineWidth = 1.4
        ember.alpha = 0.6
        ember.blendMode = .add
        ember.zPosition = 4
        sun.addChild(ember)

        let grow = SKAction.scale(to: 5.0, duration: 3.4)
        grow.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 3.4)
        ember.run(.group([grow, fade])) { ember.removeFromParent() }
    }

    // MARK: - Update: connections

    func update(connections: [Connection]) {
        let buckets = RingAssignment.bucket(connections)
        var seen = Set<UUID>()

        for ring in SacredRing.allCases {
            let bucket = buckets[ring] ?? []
            // Sort: unread first, then most recent, then alphabetical.
            // Keeps the most "alive" planets visible on the leading
            // arc when the user opens the view.
            let sorted = bucket.sorted { lhs, rhs in
                if lhs.unreadCount != rhs.unreadCount { return lhs.unreadCount > rhs.unreadCount }
                let l = FriendsDates.parse(lhs.lastMessageAt)
                let r = FriendsDates.parse(rhs.lastMessageAt)
                if l != r {
                    if let l, let r { return l > r }
                    return l != nil
                }
                return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
            }

            layout(ring: ring, connections: sorted)
            for conn in sorted { seen.insert(conn.id) }
        }

        // Drop sprites whose connection went away.
        for (id, sprite) in planetSprites where !seen.contains(id) {
            sprite.removeFromParent()
            planetSprites.removeValue(forKey: id)
        }
    }

    private func layout(ring: SacredRing, connections: [Connection]) {
        guard let orbit = orbits[ring], !connections.isEmpty else { return }
        let radius = ringRadius(ring)
        let count = connections.count
        let step = (2 * CGFloat.pi) / CGFloat(count)
        // Stagger inner/middle/outer so planets don't all line up
        // radially when counts happen to share a factor.
        let phase: CGFloat = {
            switch ring {
            case .inner:  return 0
            case .middle: return .pi / 6
            case .outer:  return .pi / 3
            }
        }()

        for (index, conn) in connections.enumerated() {
            let angle = phase + step * CGFloat(index)
            let pos = CGPoint(x: radius * cos(angle), y: radius * sin(angle))

            let sprite: PlanetSprite
            if let existing = planetSprites[conn.id] {
                sprite = existing
                if sprite.parent !== orbit {
                    sprite.removeFromParent()
                    orbit.addChild(sprite)
                }
            } else {
                sprite = PlanetSprite(connection: conn, ring: ring)
                orbit.addChild(sprite)
                planetSprites[conn.id] = sprite
            }
            sprite.position = pos
            sprite.update(connection: conn)
        }
    }

    // MARK: - Orbit rotation

    private func startOrbitRotations() {
        for (ring, orbit) in orbits {
            // SacredRing.angularSpeed is in radians/sec; convert to
            // SKAction's "seconds for one full rotation" form.
            let angularSpeed = ring.angularSpeed
            let duration = (2 * Double.pi) / Double(angularSpeed)
            let direction: CGFloat = ring == .middle ? -1 : 1
            let rotate = SKAction.rotate(byAngle: direction * 2 * .pi, duration: duration)
            orbit.run(.repeatForever(rotate), withKey: "spin")

            // Counter-rotate each planet so portraits stay upright while
            // the orbit container spins.
            // We achieve this by adding a counter-rotation action keyed
            // on the orbit; planets read the current parent rotation in
            // their per-frame update — see `didEvaluateActions`.
        }
    }

    override func didEvaluateActions() {
        // Counter-rotate planets so portraits stay upright while the
        // orbit container spins around the sun.
        for orbit in orbits.values {
            let parentZ = orbit.zRotation + world.zRotation
            for child in orbit.children {
                guard let planet = child as? PlanetSprite else { continue }
                planet.zRotation = -parentZ
            }
        }
    }

    // MARK: - Geometry helpers

    /// Ring radius in points. Tuned so all three rings + a comfortable
    /// margin fit a 360pt-wide phone in default zoom.
    private func ringRadius(_ ring: SacredRing) -> CGFloat {
        switch ring {
        case .inner:  return 95
        case .middle: return 155
        case .outer:  return 215
        }
    }

    // MARK: - Motion / reduce motion

    /// Global motion multiplier. 0.5 = half speed (the meditative
    /// default — orbits, breath, twinkles, drifts all halved). 0 =
    /// frozen, used when Reduce Motion is on.
    private static let motionScale: CGFloat = 0.5

    private func applyReduceMotion() {
        // SKNode.speed propagates: children's effective action speed
        // is the product of all ancestor speeds. Setting it once on
        // `world` is enough to scale every animated layer (nebula
        // drift, star twinkles, sun breath, orbit rotation, halo
        // pulses) in lockstep.
        world.speed = reduceMotion ? 0 : Self.motionScale
    }

    // MARK: - Gestures

    private func installGestures(on view: SKView) {
        // didMove(to:) can fire more than once if the SKView recycles —
        // detach only the recognizers WE installed last time. Touching
        // SpriteView's own recognizers (if any) would break its
        // internal touch routing.
        for gr in installedRecognizers {
            view.removeGestureRecognizer(gr)
        }
        installedRecognizers.removeAll()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)

        let dbl = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        view.addGestureRecognizer(dbl)
        tap.require(toFail: dbl)

        installedRecognizers = [pan, pinch, tap, dbl]
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let view = self.view else { return }
        let translation = gr.translation(in: view)
        switch gr.state {
        case .began:
            dragSession = CGVector(dx: world.position.x, dy: world.position.y)
        case .changed:
            // Treat horizontal drag as rotating the camera around the
            // sun, vertical drag as a small translation. Feels closer
            // to "orbiting" than pure pan-and-scan.
            let rot = -Double(translation.x) * 0.004
            world.zRotation = CGFloat(rot)
            if let session = dragSession {
                world.position = CGPoint(x: session.dx, y: session.dy - translation.y * 0.6)
            }
        case .ended, .cancelled:
            // Snap small offsets back to center so the world doesn't
            // drift over time. Rotation is sticky — that's the user's
            // chosen orbit angle.
            let snap = SKAction.move(to: CGPoint(x: world.position.x, y: 0),
                                     duration: 0.4)
            snap.timingMode = .easeOut
            world.run(snap)
            dragSession = nil
        default: break
        }
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        switch gr.state {
        case .began:
            baseScale = world.xScale
        case .changed:
            let target = max(minScale, min(maxScale, baseScale * gr.scale))
            world.setScale(target)
        case .ended, .cancelled:
            // Light haptic at the rails so users feel the bounds.
            if world.xScale <= minScale + 0.01 || world.xScale >= maxScale - 0.01 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        default: break
        }
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let view = self.view else { return }
        let pointInView = gr.location(in: view)
        let pointInScene = convertPoint(fromView: pointInView)

        // Walk the hit chain looking for a PlanetSprite — the avatar
        // and halo are children of the sprite, both should count as
        // hits on the planet.
        for node in nodes(at: pointInScene) {
            var n: SKNode? = node
            while let cur = n {
                if let planet = cur as? PlanetSprite {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    planet.flashTap()
                    onTap?(planet.connectionId)
                    return
                }
                n = cur.parent
            }
        }
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        resetCamera()
    }

    /// Spring the world back to its default rotation, position, and
    /// zoom. Triggered by double-tap or by an external SwiftUI button
    /// in solar mode.
    func resetCamera() {
        let reset = SKAction.group([
            .rotate(toAngle: defaultRotation, duration: 0.4, shortestUnitArc: true),
            .move(to: defaultPosition, duration: 0.4),
            .scale(to: 1.0, duration: 0.4)
        ])
        reset.timingMode = .easeInEaseOut
        world.run(reset)
        baseScale = 1.0
        pinchScale = 1.0
        dragAccumulated = .zero
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Star texture

    /// Build a small soft-disc texture once and reuse it across every
    /// star sprite. SKShapeNode for hundreds of stars would tank perf;
    /// a shared texture keeps it cheap.
    private static func makeStarTexture(radius: CGFloat, alpha: CGFloat) -> SKTexture {
        let size = CGSize(width: radius * 4, height: radius * 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [
                UIColor(white: 1.0, alpha: alpha).cgColor,
                UIColor(white: 1.0, alpha: 0).cgColor
            ]
            let cs = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
            cg.drawRadialGradient(gradient,
                                  startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: radius * 2,
                                  options: [])
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }
}

// MARK: - PlanetSprite

/// One planet — represents a single connection. Layered nodes:
///   • outer halo (recency-driven glow)
///   • avatar disc (image or initials fallback)
///   • unread badge (gold dot, top-right, when unreadCount > 0)
///   • optional comet trail particle when active < 48h
final class PlanetSprite: SKNode {
    let connectionId: UUID
    private var ring: SacredRing
    private var lastConnection: Connection

    private let halo: SKShapeNode
    private let avatarDisc: SKSpriteNode
    private let initialsLabel: SKLabelNode
    private var unreadBadge: SKShapeNode?
    private var inAppBadge: SKShapeNode?
    private var trail: SKEmitterNode?

    fileprivate static let avatarCache = NSCache<NSString, UIImage>()

    init(connection: Connection, ring: SacredRing) {
        self.connectionId = connection.id
        self.ring = ring
        self.lastConnection = connection

        let radius = Self.diameter(for: ring) / 2
        self.halo = SKShapeNode(circleOfRadius: radius * 1.55)
        halo.fillColor = .clear
        halo.strokeColor = UIColor.sacredGoldShine
        halo.lineWidth = 1.2
        halo.alpha = 0.0
        halo.blendMode = .add
        halo.zPosition = 0

        self.avatarDisc = SKSpriteNode(color: UIColor.sacredCosmicBgCard,
                                       size: CGSize(width: radius * 2, height: radius * 2))
        avatarDisc.zPosition = 1

        self.initialsLabel = SKLabelNode(text: "")
        initialsLabel.fontName = Self.preferredSerifFontName
        initialsLabel.fontSize = radius * 0.95
        initialsLabel.fontColor = UIColor.sacredGoldShine
        initialsLabel.verticalAlignmentMode = .center
        initialsLabel.horizontalAlignmentMode = .center
        initialsLabel.zPosition = 2

        super.init()

        // Round mask the avatar disc with a crop node so the texture
        // (whether async-loaded image or solid fallback) reads as a
        // planet, not a square.
        let crop = SKCropNode()
        crop.zPosition = 1
        let mask = SKShapeNode(circleOfRadius: radius)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        crop.addChild(avatarDisc)
        crop.addChild(initialsLabel)

        let rim = SKShapeNode(circleOfRadius: radius)
        rim.strokeColor = UIColor.sacredGoldShine
        rim.fillColor = .clear
        rim.lineWidth = 1.0
        rim.alpha = 0.25
        rim.zPosition = 3

        // The avatar body (crop + rim) breathes inside the static halo
        // — a subtle scale pulse, randomized period and starting phase
        // per planet so the circle doesn't pulse in lockstep.
        let avatarBody = SKNode()
        avatarBody.addChild(crop)
        avatarBody.addChild(rim)

        addChild(halo)
        addChild(avatarBody)

        let period = TimeInterval.random(in: 2.6...3.8)
        let grow = SKAction.scale(to: 1.05, duration: period / 2)
        grow.timingMode = .easeInEaseOut
        let shrink = SKAction.scale(to: 0.95, duration: period / 2)
        shrink.timingMode = .easeInEaseOut
        let phase = TimeInterval.random(in: 0...period)
        avatarBody.run(.sequence([
            .wait(forDuration: phase),
            .repeatForever(.sequence([grow, shrink]))
        ]))

        // Don't call update(connection:) here — the scene's layout()
        // calls it right after attaching the sprite to its orbit, at
        // which point self.scene is non-nil so the comet trail can
        // bind targetNode to world space.
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Update

    func update(connection: Connection) {
        let initials = Self.initials(from: connection.displayLabel)
        if initialsLabel.text != initials {
            initialsLabel.text = initials
        }

        applyRecency(connection: connection)
        applyUnread(connection: connection)
        applyInAppBadge(connection: connection)
        loadAvatarIfNeeded(url: connection.person.avatarUrl)

        lastConnection = connection
    }

    private func applyRecency(connection: Connection) {
        let recency = Self.recencyFactor(for: connection)

        // Halo intensity scales with recency, with a small inner-ring
        // floor so family always reads as warm.
        let baseline: CGFloat = (ring == .inner) ? 0.05 : 0.0
        let target = baseline + CGFloat(recency) * 0.21
        halo.removeAction(forKey: "haloFade")
        halo.run(SKAction.fadeAlpha(to: target, duration: 0.4), withKey: "haloFade")

        // Pulse halo when active in the last 48h — calls attention to
        // the freshest connections without being noisy.
        if recency >= 0.6 {
            if halo.action(forKey: "halo-pulse") == nil {
                let grow = SKAction.scale(to: 1.18, duration: 1.2)
                grow.timingMode = .easeInEaseOut
                let shrink = SKAction.scale(to: 1.0, duration: 1.2)
                shrink.timingMode = .easeInEaseOut
                halo.run(.repeatForever(.sequence([grow, shrink])), withKey: "halo-pulse")
            }
            ensureCometTrail()
        } else {
            halo.removeAction(forKey: "halo-pulse")
            halo.setScale(1.0)
            removeCometTrail()
        }
    }

    private func applyUnread(connection: Connection) {
        let needsBadge = connection.unreadCount > 0
        if needsBadge && unreadBadge == nil {
            let radius = Self.diameter(for: ring) / 2
            let badge = SKShapeNode(circleOfRadius: max(4, radius * 0.22))
            badge.fillColor = UIColor.sacredGoldShine
            badge.strokeColor = UIColor.sacredCosmicBg
            badge.lineWidth = 1.2
            badge.position = CGPoint(x: radius * 0.72, y: radius * 0.72)
            badge.zPosition = 5
            addChild(badge)
            unreadBadge = badge
        } else if !needsBadge, let badge = unreadBadge {
            badge.removeFromParent()
            unreadBadge = nil
        }
    }

    /// Bottom-right gold-ringed dot — marks Persons that are real
    /// ShantiSangha accounts (vs. local contacts). Same signal the
    /// ConnectionDetailView avatar overlay carries; placement here is
    /// the bottom-right so it doesn't clash with the unread dot at
    /// top-right. Pure SKShapeNode primitives — SF Symbol via
    /// SKTexture renders unreliably inside small sprites.
    private func applyInAppBadge(connection: Connection) {
        let needsBadge = connection.person.userId != nil
        if needsBadge && inAppBadge == nil {
            let radius = Self.diameter(for: ring) / 2
            let badgeRadius = max(6, radius * 0.26)
            let badge = SKShapeNode(circleOfRadius: badgeRadius)
            badge.fillColor = UIColor.sacredCosmicBg
            badge.strokeColor = UIColor.sacredGoldShine.withAlphaComponent(0.9)
            badge.lineWidth = 1.5
            badge.position = CGPoint(x: radius * 0.72, y: -radius * 0.72)
            badge.zPosition = 5

            // Inner gold dot — reads as a "pearl" / verified marker.
            let inner = SKShapeNode(circleOfRadius: badgeRadius * 0.48)
            inner.fillColor = UIColor.sacredGoldShine
            inner.strokeColor = .clear
            inner.zPosition = 1
            badge.addChild(inner)

            addChild(badge)
            inAppBadge = badge
        } else if !needsBadge, let badge = inAppBadge {
            badge.removeFromParent()
            inAppBadge = nil
        }
    }

    private func ensureCometTrail() {
        if let emitter = trail {
            // Re-bind targetNode in case the sprite was re-parented
            // (e.g. a relation change moved the planet to a new ring).
            emitter.targetNode = self.scene
            return
        }
        let emitter = Self.makeCometEmitter(ring: ring)
        emitter.zPosition = -1
        addChild(emitter)
        emitter.targetNode = self.scene
        trail = emitter
    }

    private func removeCometTrail() {
        trail?.removeFromParent()
        trail = nil
    }

    func flashTap() {
        let pop = SKAction.sequence([
            .scale(to: 1.18, duration: 0.08),
            .scale(to: 1.0, duration: 0.18)
        ])
        run(pop)
        let spark = SKAction.sequence([
            .fadeAlpha(to: 1.0, duration: 0.08),
            .fadeAlpha(to: halo.alpha, duration: 0.4)
        ])
        halo.run(spark)
    }

    // MARK: - Avatar loading

    private func loadAvatarIfNeeded(url: String?) {
        guard let url = url, let parsed = URL(string: url) else {
            avatarDisc.texture = nil
            avatarDisc.color = Self.fallbackColor(for: connectionId)
            initialsLabel.alpha = 1.0
            return
        }

        // See `CircleSpriteScene.avatarCacheKey(for:)` — strip the S3
        // presigned query so the same image survives `/me` reloads.
        let key = CircleSpriteScene.avatarCacheKey(for: parsed)
        if let cached = Self.avatarCache.object(forKey: key) {
            applyAvatar(cached)
            return
        }

        URLSession.shared.dataTask(with: parsed) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, let image = UIImage(data: data) else { return }
            Self.avatarCache.setObject(image, forKey: key)
            DispatchQueue.main.async {
                self.applyAvatar(image)
            }
        }.resume()
    }

    private func applyAvatar(_ image: UIImage) {
        let texture = SKTexture(image: image)
        avatarDisc.texture = texture
        avatarDisc.color = .white
        avatarDisc.colorBlendFactor = 0
        // Hide initials once the image is on — the initial fallback
        // remains underneath while the texture loads.
        initialsLabel.alpha = 0
    }

    // MARK: - Statics

    private static func diameter(for ring: SacredRing) -> CGFloat {
        switch ring {
        case .inner:  return 44
        case .middle: return 36
        case .outer:  return 30
        }
    }

    /// Stable warm tone per connection so locals without avatar URLs
    /// don't all share the same brown. Hash the UUID to pick a hue
    /// inside the saffron/amber band.
    private static func fallbackColor(for id: UUID) -> UIColor {
        let hash = id.uuidString.hashValue
        let hue = (CGFloat(abs(hash) % 360) / 360.0) * 0.13 + 0.06   // 0.06..0.19 (warm only)
        return UIColor(hue: hue, saturation: 0.55, brightness: 0.42, alpha: 1.0)
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "·" : letters.uppercased()
    }

    private static func recencyFactor(for connection: Connection) -> Double {
        guard let date = FriendsDates.parse(connection.lastMessageAt) else { return 0 }
        let hours = Date().timeIntervalSince(date) / 3600.0
        if hours <= 48 { return 1.0 }
        if hours > 720 { return 0 }
        return max(0, 1.0 - ((hours - 48) / (720 - 48)))
    }

    private static func makeCometEmitter(ring: SacredRing) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeSparkTexture()
        emitter.particleBirthRate = 18
        emitter.particleLifetime = 1.4
        emitter.particleLifetimeRange = 0.6
        emitter.particleAlpha = 0.7
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.5
        emitter.particleScale = 0.55
        emitter.particleScaleRange = 0.25
        emitter.particleScaleSpeed = -0.3
        emitter.particleColor = UIColor.sacredGoldShine
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.emissionAngle = .pi   // emit "behind" along orbit tangent
        emitter.emissionAngleRange = .pi / 6
        emitter.particleSpeed = ring == .inner ? 18 : 10
        emitter.particleSpeedRange = 6
        emitter.particlePositionRange = CGVector(dx: 4, dy: 4)
        return emitter
    }

    /// Resolve a serif PostScript name once, falling back to Georgia
    /// if the New York family isn't installed (very old simulators).
    /// SKLabelNode takes a name string — there's no `design: .serif`
    /// shortcut like SwiftUI has.
    fileprivate static let preferredSerifFontName: String = {
        for candidate in ["NewYorkLarge-Semibold", "NewYork-Semibold", "Georgia-Bold"] {
            if UIFont(name: candidate, size: 12) != nil { return candidate }
        }
        return "Georgia"
    }()

    private static func makeSparkTexture() -> SKTexture {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [
                UIColor(white: 1.0, alpha: 1.0).cgColor,
                UIColor(white: 1.0, alpha: 0).cgColor
            ]
            let cs = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
            cg.drawRadialGradient(gradient,
                                  startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: 7,
                                  options: [])
        }
        return SKTexture(image: image)
    }
}

// MARK: - Sacred palette bridges

/// SpriteKit takes `UIColor`, not SwiftUI `Color`. These bridges resolve
/// the sacred design tokens once for SpriteKit consumption. Adaptive
/// tokens (`sacredBg`, `sacredBgCard`, `sacredText`, `sacredMuted`) are
/// pinned to their **dark** variants — the solar visualization is
/// intentionally cosmic-dark regardless of system appearance, so stars,
/// nebula, and ember glow read crisply against the warm parchment
/// `SacredBackground` showing through from the parent.
private extension UIColor {
    static let sacredGold = UIColor(SwiftUI.Color.sacredGold)
    static let sacredGoldDark = UIColor(SwiftUI.Color.sacredGoldDark)
    static let sacredGoldLight = UIColor(SwiftUI.Color.sacredGoldLight)
    static let sacredGoldShine = UIColor(SwiftUI.Color.sacredGoldShine)

    static let sacredCosmicBg = UIColor(SwiftUI.Color.sacredBg)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    static let sacredCosmicBgCard = UIColor(SwiftUI.Color.sacredBgCard)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    static let sacredCosmicText = UIColor(SwiftUI.Color.sacredText)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    static let sacredCosmicMuted = UIColor(SwiftUI.Color.sacredMuted)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
}
