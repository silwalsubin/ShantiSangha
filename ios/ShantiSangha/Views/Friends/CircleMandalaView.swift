import SwiftUI

/// Visual mandala of the user's circle: you at the center, your
/// connections placed in three concentric rings by relational
/// closeness (inner = family, middle = close friends/siblings,
/// outer = colleagues/other). Sub-pixel breathing keeps the
/// composition feeling alive without being restless.
///
/// Renders pure SwiftUI shapes — no Canvas, no SpriteKit, no
/// WebView, no third-party library. The node count is bounded by
/// human relational reality (rarely > 100), so the diff cost stays
/// trivial and hit-testing is just per-node Buttons.
struct CircleMandalaView: View {
    let connections: [Connection]
    let onTap: (UUID) -> Void
    @EnvironmentObject private var profile: ProfileService

    /// Persisted across gestures. Pinch updates `magnification` live;
    /// drag updates `dragOffset` live. On gesture-end we fold them
    /// into `scale`/`offset` and clamp.
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero

    private static let minScale: CGFloat = 1.0
    private static let maxScale: CGFloat = 3.0

    var body: some View {
        GeometryReader { geo in
            let layout = MandalaLayout(size: geo.size, connections: connections)
            let liveScale = clampScale(scale * magnification)
            let liveOffset = clampOffset(
                CGSize(width: offset.width + dragOffset.width,
                       height: offset.height + dragOffset.height),
                scale: liveScale,
                size: geo.size)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    background(layout: layout)
                    spokes(layout: layout, t: t)
                    ringLabels(layout: layout)
                    ringNodes(layout: layout, t: t)
                    centerYou(layout: layout)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .scaleEffect(liveScale, anchor: .center)
            .offset(liveOffset)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .updating($magnification) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        let newScale = clampScale(scale * value)
                        scale = newScale
                        // Re-clamp offset against the new scale —
                        // zooming out should pull a panned mandala
                        // back toward center so it doesn't strand
                        // off-screen.
                        offset = clampOffset(offset, scale: newScale, size: geo.size)
                    }
            )
            .simultaneousGesture(
                // Min distance > 0 keeps short presses from competing
                // with node-tap Buttons inside. Drag only engages once
                // the user is meaningfully zoomed in — no point
                // panning a 1.0x mandala that already fits the frame.
                DragGesture(minimumDistance: 12)
                    .updating($dragOffset) { value, state, _ in
                        guard scale > 1.01 else { return }
                        state = value.translation
                    }
                    .onEnded { value in
                        guard scale > 1.01 else { return }
                        let proposed = CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            offset = clampOffset(proposed, scale: scale, size: geo.size)
                        }
                    }
            )
            .onTapGesture(count: 2) {
                // Quick reset — the discoverable escape hatch from a
                // zoomed-in state. iMessage / Photos use the same
                // double-tap convention.
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    scale = 1.0
                    offset = .zero
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    // MARK: - Zoom helpers

    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, Self.minScale), Self.maxScale)
    }

    /// Bound the pan so the scaled content can't be dragged completely
    /// off-screen. The accessible pan range is exactly half the extra
    /// content created by scaling — beyond that, you'd just see the
    /// page background.
    private func clampOffset(_ proposed: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        let maxX = max(0, (scale - 1) * size.width / 2)
        let maxY = max(0, (scale - 1) * size.height / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY))
    }

    // MARK: - Layers

    private func background(layout: MandalaLayout) -> some View {
        // Soft saffron glow at the center, fading through the page
        // background out to the edges. In dark mode this reads as a
        // warm parchment halo against deep brown.
        RadialGradient(
            colors: [
                Color.sacredGold.opacity(0.18),
                Color.sacredBg.opacity(0.6),
                Color.sacredBgCard.opacity(0.0)
            ],
            center: .center,
            startRadius: 0,
            endRadius: layout.outerRadius * 1.4)
    }

    private func spokes(layout: MandalaLayout, t: TimeInterval) -> some View {
        ZStack {
            // Layer 1: regular spokes — single Path, uniform faint gold.
            // Skips connections that are recently-messaged so layer 2
            // doesn't double-stroke.
            Path { path in
                for ring in MandalaRing.allCases {
                    let ringConnections = layout.connections(in: ring)
                    let radius = layout.radius(for: ring)
                    for (i, conn) in ringConnections.enumerated() where !isRecent(conn) {
                        let angle = layout.angle(index: i, count: ringConnections.count)
                        let breath = breathOffset(for: conn, angle: angle, t: t)
                        let endX = layout.center.x + radius * cos(angle) + breath.dx
                        let endY = layout.center.y + radius * sin(angle) + breath.dy
                        path.move(to: layout.center)
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                }
            }
            .stroke(Color.sacredGold.opacity(0.12), lineWidth: 0.5)

            // Layer 2: recent spokes — one Shape per spoke so each can
            // carry a directional LinearGradient (cool at center, warm
            // at the connection). Per-spoke shape allocation only
            // happens for the small set of recently-messaged rows.
            ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
                let ringConnections = layout.connections(in: ring)
                let radius = layout.radius(for: ring)
                ForEach(Array(ringConnections.enumerated()), id: \.element.id) { i, conn in
                    if isRecent(conn) {
                        let angle = layout.angle(index: i, count: ringConnections.count)
                        let breath = breathOffset(for: conn, angle: angle, t: t)
                        let end = CGPoint(
                            x: layout.center.x + radius * cos(angle) + breath.dx,
                            y: layout.center.y + radius * sin(angle) + breath.dy)
                        SpokeLine(start: layout.center, end: end)
                            .stroke(spokeGradient(start: layout.center, end: end),
                                    lineWidth: 0.8)
                    }
                }
            }
        }
    }

    /// Gradient pointing along a single spoke from the center (cool)
    /// out to the connection (warm). LinearGradient as a ShapeStyle is
    /// bbox-relative, so we map both endpoints to bbox-local UnitPoints
    /// — that's the only way the gradient direction matches the line's
    /// actual direction across all four quadrants.
    private func spokeGradient(start: CGPoint, end: CGPoint) -> LinearGradient {
        let bboxMinX = min(start.x, end.x)
        let bboxMinY = min(start.y, end.y)
        let bboxW = max(abs(end.x - start.x), 0.001)
        let bboxH = max(abs(end.y - start.y), 0.001)
        return LinearGradient(
            colors: [
                Color.sacredGold.opacity(0.10),
                Color.sacredGold.opacity(0.50)
            ],
            startPoint: UnitPoint(
                x: (start.x - bboxMinX) / bboxW,
                y: (start.y - bboxMinY) / bboxH),
            endPoint: UnitPoint(
                x: (end.x - bboxMinX) / bboxW,
                y: (end.y - bboxMinY) / bboxH))
    }

    private func ringLabels(layout: MandalaLayout) -> some View {
        ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
            // Skip the label for empty rings — no orientation aid
            // needed when there's nothing to orient toward.
            if !layout.connections(in: ring).isEmpty {
                Text(ring.label)
                    .font(.sacredSectionLabel)
                    .foregroundColor(.sacredLabel.opacity(0.5))
                    .offset(x: 0, y: -(layout.radius(for: ring) + 26))
            }
        }
    }

    private func ringNodes(layout: MandalaLayout, t: TimeInterval) -> some View {
        ZStack {
            ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
                let ringConnections = layout.connections(in: ring)
                let avatarSize = layout.avatarSize(forCount: ringConnections.count)
                let radius = layout.radius(for: ring)
                ForEach(Array(ringConnections.enumerated()), id: \.element.id) { i, conn in
                    let angle = layout.angle(index: i, count: ringConnections.count)
                    let breath = breathOffset(for: conn, angle: angle, t: t)
                    let baseX = radius * cos(angle)
                    let baseY = radius * sin(angle)

                    Button { onTap(conn.id) } label: {
                        nodeLabel(conn, ring: ring, avatarSize: avatarSize)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: layout.center.x + baseX + breath.dx,
                        y: layout.center.y + baseY + breath.dy)
                }
            }
        }
    }

    private func nodeLabel(_ conn: Connection, ring: MandalaRing, avatarSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            SacredAvatar(
                displayName: conn.displayLabel,
                avatarUrl: conn.person.avatarUrl,
                size: avatarSize)
                .overlay(
                    Circle().stroke(ringColor(ring: ring, recent: isRecent(conn)),
                                    lineWidth: 1.5)
                )
                .padding(.bottom, 2)
            Text(conn.displayLabel)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(avatarSize + 28, 60))
            // Relation chip — quiet on the periphery, readable on focus.
            // Lowercase + light tracking respects custom labels like "yoga
            // teacher" that look ugly in tracked-out caps.
            Text(conn.relationLabel.lowercased())
                .font(.system(size: 9, weight: .medium, design: .serif))
                .tracking(0.6)
                .foregroundColor(.sacredLabel.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(avatarSize + 36, 68))
        }
    }

    private func centerYou(layout: MandalaLayout) -> some View {
        ZStack {
            // Soft outer glow — concentric circles with falloff so the
            // center has visual gravity without a hard edge.
            Circle()
                .fill(Color.sacredGold.opacity(0.14))
                .frame(width: 110, height: 110)
                .blur(radius: 16)
            Circle()
                .fill(Color.sacredGold.opacity(0.10))
                .frame(width: 80, height: 80)
                .blur(radius: 8)

            SacredAvatar(
                displayName: profile.profile?.displayName ?? "You",
                avatarUrl: profile.profile?.avatarUrl,
                size: 60)
                .overlay(
                    Circle().stroke(Color.sacredGold.opacity(0.7), lineWidth: 2)
                )
        }
        .position(x: layout.center.x, y: layout.center.y)
    }

    // MARK: - Helpers

    /// Per-node breathing offset. Each node oscillates radially (in
    /// and out from the center) by ~1.5pt on a 10-second cycle, with
    /// a stable phase derived from the connection id so they don't
    /// move in unison. Stable across launches because it uses the
    /// raw UUID bytes, not Swift's randomized String.hash.
    private func breathOffset(for conn: Connection, angle: CGFloat, t: TimeInterval) -> (dx: CGFloat, dy: CGFloat) {
        let phaseSeed = withUnsafeBytes(of: conn.id.uuid) { Double($0[0]) / 255.0 }
        let phase = phaseSeed * .pi * 2
        let breath = sin(t * 2 * .pi / 10.0 + phase) * 1.5
        // Mostly-radial drift so the composition feels like a slow
        // inhale/exhale rather than a swirl.
        return (dx: CGFloat(breath) * cos(angle) * 0.7,
                dy: CGFloat(breath) * sin(angle) * 0.7)
    }

    private func isRecent(_ conn: Connection) -> Bool {
        guard let iso = conn.lastMessageAt else { return false }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            return Date().timeIntervalSince(d) < 48 * 60 * 60
        }
        // Fallback for timestamps without fractional seconds.
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) {
            return Date().timeIntervalSince(d) < 48 * 60 * 60
        }
        return false
    }

    /// Border color tightens (warmer, more opaque) for inner rings
    /// and again for connections you've messaged in the last 48h.
    /// Visual depth — closer feels warmer; alive feels alive.
    private func ringColor(ring: MandalaRing, recent: Bool) -> Color {
        let base: Double = switch ring {
        case .inner:  0.6
        case .middle: 0.4
        case .outer:  0.25
        }
        return Color.sacredGold.opacity(recent ? min(base + 0.25, 0.95) : base)
    }
}

// MARK: - Helpers

/// One straight-line spoke. Wrapped in its own Shape so per-spoke
/// gradient strokes work cleanly — `LinearGradient` as a `ShapeStyle`
/// is bbox-relative, so each line needs its own Shape for the
/// gradient direction to match the line's actual direction.
private struct SpokeLine: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: start)
            p.addLine(to: end)
        }
    }
}

// MARK: - Layout

private struct MandalaLayout {
    let size: CGSize

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    var minDim: CGFloat { min(size.width, size.height) }

    /// Hard ceiling so the outermost avatar circle never crosses the
    /// screen edge, regardless of how much room the proportions ask for.
    private var outerCap: CGFloat { minDim / 2 - 36 }

    var innerRadius: CGFloat  { min(0.18 * minDim, outerCap - 120) }
    var middleRadius: CGFloat { min(0.34 * minDim, outerCap - 60) }
    var outerRadius: CGFloat  { min(0.50 * minDim, outerCap) }

    func radius(for ring: MandalaRing) -> CGFloat {
        switch ring {
        case .inner:  return innerRadius
        case .middle: return middleRadius
        case .outer:  return outerRadius
        }
    }

    /// Even angular distribution starting at the top (12 o'clock).
    func angle(index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return -.pi / 2 }
        return -.pi / 2 + (CGFloat(index) / CGFloat(count)) * .pi * 2
    }

    /// Connections sorted deterministically per ring so refreshes don't
    /// shuffle positions. Sort by displayLabel then id — quiet and
    /// stable.
    let connections: [Connection]

    init(size: CGSize, connections: [Connection] = []) {
        self.size = size
        self.connections = connections
    }

    /// Pre-bucketed and pre-sorted connections so the body recomputes
    /// at most once per render. Sorted deterministically by displayLabel
    /// then id so refreshes don't shuffle positions.
    private var bucketedByRing: [MandalaRing: [Connection]] {
        var buckets: [MandalaRing: [Connection]] = [:]
        for ring in MandalaRing.allCases { buckets[ring] = [] }
        for conn in connections {
            let type = ConnectionType(rawValue: conn.relationType.lowercased()) ?? .other
            buckets[MandalaRing.ring(for: type), default: []].append(conn)
        }
        for ring in MandalaRing.allCases {
            buckets[ring]?.sort {
                let cmp = $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        return buckets
    }

    func connections(in ring: MandalaRing) -> [Connection] {
        bucketedByRing[ring] ?? []
    }

    /// Avatars shrink as a ring fills up so they don't crowd. Past 24
    /// in a single ring we'd want pagination/clustering — punt to a
    /// follow-up.
    func avatarSize(forCount count: Int) -> CGFloat {
        switch count {
        case ...12: return 44
        case 13...18: return 36
        default: return 28
        }
    }
}

// MARK: - Ring taxonomy

enum MandalaRing: Int, CaseIterable {
    case inner = 0, middle, outer

    static func ring(for type: ConnectionType) -> MandalaRing {
        switch type {
        case .spouse, .parent, .child: return .inner
        case .sibling, .friend:        return .middle
        case .colleague, .other:       return .outer
        }
    }

    var label: String {
        switch self {
        case .inner:  return "FAMILY"
        case .middle: return "CLOSE"
        case .outer:  return "BROADER"
        }
    }
}

