import SwiftUI
import Charts

/// Visual mandala of the user's circle: you at the center, your
/// connections placed in three concentric rings by relational
/// closeness (inner = family, middle = close friends/siblings,
/// outer = colleagues/other). Small circles breathe gently; large
/// circles render a bounded focus set with overflow counts so the
/// tab stays smooth even when the directory holds hundreds of people.
///
/// Chart3D renders the depth field; native SwiftUI avatar nodes keep
/// hit targets, names, and profile/chat navigation precise. Hit
/// testing is limited to visible focus nodes; the full, searchable
/// directory lives in FriendsTabView.
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

            Group {
                if layout.shouldAnimate {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        mandalaLayers(
                            layout: layout,
                            t: context.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    mandalaLayers(layout: layout, t: 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
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

    private func mandalaLayers(layout: MandalaLayout, t: TimeInterval) -> some View {
        ZStack {
            background(layout: layout)
            chart3DField(layout: layout)
            ringGuides(layout: layout)
            spokes(layout: layout, t: t)
            ringLabels(layout: layout)
            ringNodes(layout: layout, t: t)
            overflowBadges(layout: layout)
            centerYou(layout: layout)
        }
    }

    private func chart3DField(layout: MandalaLayout) -> some View {
        CircleChart3DField(points: layout.chartPoints)
            .frame(width: layout.size.width, height: layout.size.height)
            .opacity(layout.usesFocusSet ? 0.78 : 0.62)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

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

    private func ringGuides(layout: MandalaLayout) -> some View {
        ZStack {
            ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
                if layout.totalCount(in: ring) > 0 {
                    Circle()
                        .stroke(Color.sacredGold.opacity(ring.guideOpacity),
                                style: StrokeStyle(lineWidth: 0.8, dash: [2, 8]))
                        .frame(width: layout.radius(for: ring) * 2,
                               height: layout.radius(for: ring) * 2)
                        .position(layout.center)
                }
            }
        }
    }

    private func spokes(layout: MandalaLayout, t: TimeInterval) -> some View {
        ZStack {
            // Layer 1: regular spokes — single Path, uniform faint gold.
            // Skips connections that are recently-messaged so layer 2
            // doesn't double-stroke.
            Path { path in
                for ring in MandalaRing.allCases {
                    let ringConnections = layout.visibleConnections(in: ring)
                    let radius = layout.radius(for: ring)
                    for (i, conn) in ringConnections.enumerated() where !layout.isRecent(conn) {
                        let angle = layout.angle(index: i, count: ringConnections.count, ring: ring)
                        let breath = breathOffset(for: conn, angle: angle, t: t)
                        let endX = layout.center.x + radius * cos(angle) + breath.dx
                        let endY = layout.center.y + radius * sin(angle) + breath.dy
                        path.move(to: layout.center)
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                }
            }
            .stroke(Color.sacredGold.opacity(layout.spokeOpacity), lineWidth: 0.5)

            // Layer 2: recent spokes — one Shape per spoke so each can
            // carry a directional LinearGradient (cool at center, warm
            // at the connection). Per-spoke shape allocation only
            // happens for the small set of recently-messaged rows.
            ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
                let ringConnections = layout.visibleConnections(in: ring)
                let radius = layout.radius(for: ring)
                ForEach(Array(ringConnections.enumerated()), id: \.element.id) { i, conn in
                    if layout.isRecent(conn) {
                        let angle = layout.angle(index: i, count: ringConnections.count, ring: ring)
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
            if layout.totalCount(in: ring) > 0 {
                Text(ringLabel(ring, layout: layout))
                    .font(.sacredSectionLabel)
                    .foregroundColor(.sacredLabel.opacity(0.5))
                    .offset(x: 0, y: -(layout.radius(for: ring) + 26))
            }
        }
    }

    private func ringLabel(_ ring: MandalaRing, layout: MandalaLayout) -> String {
        let total = layout.totalCount(in: ring)
        guard layout.usesFocusSet else { return ring.label }
        return "\(ring.label) \(total.formatted())"
    }

    private func ringNodes(layout: MandalaLayout, t: TimeInterval) -> some View {
        ZStack {
            ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
                let ringConnections = layout.visibleConnections(in: ring)
                let avatarSize = layout.avatarSize(
                    forVisibleCount: ringConnections.count,
                    totalCount: layout.totalCount(in: ring))
                let radius = layout.radius(for: ring)
                ForEach(Array(ringConnections.enumerated()), id: \.element.id) { i, conn in
                    let angle = layout.angle(index: i, count: ringConnections.count, ring: ring)
                    let breath = breathOffset(for: conn, angle: angle, t: t)
                    let baseX = radius * cos(angle)
                    let baseY = radius * sin(angle)

                    Button { onTap(conn.id) } label: {
                        nodeLabel(
                            conn,
                            ring: ring,
                            avatarSize: avatarSize,
                            showLabels: layout.shouldShowLabels(in: ring),
                            recent: layout.isRecent(conn))
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: layout.center.x + baseX + breath.dx,
                        y: layout.center.y + baseY + breath.dy)
                }
            }
        }
    }

    private func nodeLabel(
        _ conn: Connection,
        ring: MandalaRing,
        avatarSize: CGFloat,
        showLabels: Bool,
        recent: Bool
    ) -> some View {
        VStack(spacing: showLabels ? 2 : 0) {
            SacredAvatar(
                displayName: conn.displayLabel,
                avatarUrl: conn.person.avatarUrl,
                size: avatarSize)
                .overlay(
                    Circle().stroke(ringColor(ring: ring, recent: recent),
                                    lineWidth: 1.5)
                )
                .padding(.bottom, showLabels ? 2 : 0)

            if showLabels {
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
    }

    private func overflowBadges(layout: MandalaLayout) -> some View {
        ZStack {
            ForEach(MandalaRing.allCases, id: \.rawValue) { ring in
                let overflow = layout.overflowCount(in: ring)
                if overflow > 0 {
                    let angle = ring.overflowAngle
                    let radius = layout.radius(for: ring)
                    Text("+\(overflow.formatted())")
                        .font(.sacredMicroBold)
                        .foregroundColor(.sacredGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.sacredBgCard.opacity(0.88)))
                        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.22), lineWidth: 1))
                        .position(
                            x: layout.center.x + radius * cos(angle),
                            y: layout.center.y + radius * sin(angle))
                        .accessibilityLabel("\(overflow) more in \(ring.label.lowercased())")
                }
            }
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

private struct CircleChart3DField: View {
    let points: [MandalaChartPoint]

    var body: some View {
        Chart3D(points) { point in
            PointMark(
                x: .value("Horizontal", point.x),
                y: .value("Closeness", point.y),
                z: .value("Depth", point.z)
            )
            .symbol(.sphere)
            .symbolSize(point.symbolSize)
            .foregroundStyle(point.color)
        }
        .chartXScale(domain: -1.08...1.08, range: -0.5...0.5)
        .chartYScale(domain: -0.32...0.42, range: -0.24...0.34)
        .chartZScale(domain: -1.08...1.08, range: -0.5...0.5)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartZAxis(.hidden)
        .chartLegend(.hidden)
        .chart3DCameraProjection(.perspective)
    }
}

private struct MandalaChartPoint: Identifiable {
    let id: UUID
    let x: Double
    let y: Double
    let z: Double
    let symbolSize: CGFloat
    let color: Color
}

// MARK: - Layout

private struct MandalaLayout {
    private static let maxVisiblePerRing = 32
    private static let animationLimit = 72

    let size: CGSize
    let totalCount: Int
    private let visibleByRing: [MandalaRing: [Connection]]
    private let totalByRing: [MandalaRing: Int]
    private let recentIDs: Set<UUID>

    var center: CGPoint {
        CGPoint(
            x: size.width / 2,
            y: min(size.height / 2, outerRadius + 86))
    }

    var minDim: CGFloat { min(size.width, size.height) }

    /// Hard ceiling so the outermost avatar circle never crosses the
    /// screen edge, regardless of how much room the proportions ask for.
    private var outerCap: CGFloat { max(0, minDim / 2 - 34) }

    var outerRadius: CGFloat  { outerCap }
    var middleRadius: CGFloat { outerRadius * 0.66 }
    var innerRadius: CGFloat  { outerRadius * 0.40 }

    var usesFocusSet: Bool {
        MandalaRing.allCases.contains { overflowCount(in: $0) > 0 }
    }

    var shouldAnimate: Bool {
        totalVisibleCount <= Self.animationLimit
    }

    var spokeOpacity: Double {
        usesFocusSet ? 0.07 : 0.12
    }

    private var totalVisibleCount: Int {
        MandalaRing.allCases.reduce(0) { $0 + visibleConnections(in: $1).count }
    }

    var chartPoints: [MandalaChartPoint] {
        var points: [MandalaChartPoint] = [
            MandalaChartPoint(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                x: 0,
                y: 0.34,
                z: 0,
                symbolSize: 0.085,
                color: Color.sacredGold.opacity(0.9))
        ]

        for ring in MandalaRing.allCases {
            let ringConnections = visibleConnections(in: ring)
            let normalizedRadius = Double(radius(for: ring) / max(outerRadius, 1))
            for (index, conn) in ringConnections.enumerated() {
                let angle = angle(index: index, count: ringConnections.count, ring: ring)
                let recentLift = isRecent(conn) ? 0.07 : 0
                points.append(
                    MandalaChartPoint(
                        id: conn.id,
                        x: Double(cos(angle)) * normalizedRadius,
                        y: ring.chartHeight + recentLift,
                        z: Double(sin(angle)) * normalizedRadius,
                        symbolSize: chartSymbolSize(for: conn, in: ring, visibleCount: ringConnections.count),
                        color: chartColor(for: ring, recent: isRecent(conn))))
            }
        }

        return points
    }

    func radius(for ring: MandalaRing) -> CGFloat {
        switch ring {
        case .inner:  return innerRadius
        case .middle: return middleRadius
        case .outer:  return outerRadius
        }
    }

    /// Even angular distribution with per-ring phase offsets so one
    /// connection in each ring does not stack into a vertical column.
    func angle(index: Int, count: Int, ring: MandalaRing) -> CGFloat {
        guard count > 0 else { return -.pi / 2 }
        if count == 1 { return ring.singleAngle }
        return ring.startAngle + (CGFloat(index) / CGFloat(count)) * .pi * 2
    }

    init(size: CGSize, connections: [Connection] = []) {
        self.size = size
        self.totalCount = connections.count

        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        let recentIDs = Set(connections.compactMap { conn -> UUID? in
            guard let date = FriendsDates.parse(conn.lastMessageAt), date >= cutoff else { return nil }
            return conn.id
        })

        var buckets: [MandalaRing: [Connection]] = [:]
        for ring in MandalaRing.allCases { buckets[ring] = [] }
        for conn in connections {
            let type = ConnectionType(rawValue: conn.relationType.lowercased()) ?? .other
            buckets[MandalaRing.ring(for: type), default: []].append(conn)
        }

        var totals: [MandalaRing: Int] = [:]
        var visible: [MandalaRing: [Connection]] = [:]
        for ring in MandalaRing.allCases {
            buckets[ring]?.sort {
                Self.sortForFocus($0, $1, recentIDs: recentIDs)
            }
            let sorted = buckets[ring] ?? []
            totals[ring] = sorted.count
            visible[ring] = Array(sorted.prefix(Self.maxVisiblePerRing))
        }

        self.totalByRing = totals
        self.visibleByRing = visible
        self.recentIDs = recentIDs
    }

    private static func sortForFocus(_ lhs: Connection, _ rhs: Connection, recentIDs: Set<UUID>) -> Bool {
        if lhs.unreadCount != rhs.unreadCount {
            return lhs.unreadCount > rhs.unreadCount
        }

        let lhsRecent = recentIDs.contains(lhs.id)
        let rhsRecent = recentIDs.contains(rhs.id)
        if lhsRecent != rhsRecent { return lhsRecent }

        if lhs.messageable != rhs.messageable { return lhs.messageable }

        let cmp = lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func chartSymbolSize(for connection: Connection, in ring: MandalaRing, visibleCount: Int) -> CGFloat {
        let base = avatarSize(forVisibleCount: visibleCount, totalCount: totalCount(in: ring)) / 740
        let unreadBoost: CGFloat = connection.unreadCount > 0 ? 0.015 : 0
        let recentBoost: CGFloat = isRecent(connection) ? 0.01 : 0
        return min(0.075, max(0.032, base + unreadBoost + recentBoost))
    }

    private func chartColor(for ring: MandalaRing, recent: Bool) -> Color {
        let opacity: Double = switch ring {
        case .inner: 0.86
        case .middle: 0.66
        case .outer: 0.48
        }
        return Color.sacredGold.opacity(recent ? min(opacity + 0.14, 0.96) : opacity)
    }

    func visibleConnections(in ring: MandalaRing) -> [Connection] {
        visibleByRing[ring] ?? []
    }

    func totalCount(in ring: MandalaRing) -> Int {
        totalByRing[ring] ?? 0
    }

    func overflowCount(in ring: MandalaRing) -> Int {
        max(0, totalCount(in: ring) - visibleConnections(in: ring).count)
    }

    func isRecent(_ connection: Connection) -> Bool {
        recentIDs.contains(connection.id)
    }

    /// Avatars shrink as a ring fills up. When a ring is clustered,
    /// visible nodes become a focus map and labels are withheld.
    func avatarSize(forVisibleCount visibleCount: Int, totalCount: Int) -> CGFloat {
        let base: CGFloat = switch visibleCount {
        case ...5: 46
        case 6...12: 40
        case 13...20: 34
        case 21...32: 28
        default: 24
        }

        return totalCount > visibleCount ? min(base, 28) : base
    }

    func shouldShowLabels(in ring: MandalaRing) -> Bool {
        !usesFocusSet && totalCount(in: ring) <= 12
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

    var startAngle: CGFloat {
        switch self {
        case .inner:  return -.pi / 2
        case .middle: return -.pi / 6
        case .outer:  return .pi / 6
        }
    }

    var singleAngle: CGFloat {
        switch self {
        case .inner:  return -.pi / 2
        case .middle: return .pi / 6
        case .outer:  return 5 * .pi / 6
        }
    }

    var overflowAngle: CGFloat {
        switch self {
        case .inner:  return .pi
        case .middle: return .pi / 2
        case .outer:  return 0
        }
    }

    var guideOpacity: Double {
        switch self {
        case .inner:  return 0.16
        case .middle: return 0.12
        case .outer:  return 0.10
        }
    }

    var chartHeight: Double {
        switch self {
        case .inner:  return 0.18
        case .middle: return 0.03
        case .outer:  return -0.12
        }
    }
}
