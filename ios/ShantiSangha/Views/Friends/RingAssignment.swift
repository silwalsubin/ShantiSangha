import Foundation

/// Closeness classification for connections — three concentric "rings":
/// inner = family, middle = close, outer = broader. Originally part of
/// the RealityKit solar system; the SpriteKit view reuses the same
/// taxonomy.
///
/// With circle tags being free-form, ring placement now goes by a
/// known-name lookup: the historical defaults (Spouse, Parent, Child →
/// inner; Sibling, Friend → middle) keep their orbits, anything else
/// falls to the outer ring. A connection with multiple circles uses the
/// innermost ring any of its circles maps to.
enum SacredRing: Int, CaseIterable {
    case inner = 0
    case middle
    case outer

    /// Resolve a single tag name to a ring. Case-insensitive.
    static func ring(forCircleName name: String) -> SacredRing {
        switch name.lowercased() {
        case "spouse", "parent", "child", "family":
            return .inner
        case "sibling", "friend", "close":
            return .middle
        default:
            return .outer
        }
    }

    /// Pick the closest ring across a list of circle tags. Empty list
    /// (a connection with no tags yet) falls to outer.
    static func ring(forCircles circles: [String]) -> SacredRing {
        var best: SacredRing = .outer
        for name in circles {
            let r = ring(forCircleName: name)
            if r.rawValue < best.rawValue { best = r }
            if best == .inner { return best }
        }
        return best
    }

    /// Angular speed in radians per second. Inner rings orbit faster
    /// (Kepler-ish — closer bodies orbit quicker). The SpriteKit view
    /// turns this into a per-orbit duration via `2π / angularSpeed`.
    var angularSpeed: Float {
        switch self {
        case .inner:  return 0.40
        case .middle: return 0.22
        case .outer:  return 0.11
        }
    }
}

enum RingAssignment {
    /// Bucket connections by ring, preserving caller's input order.
    static func bucket(_ connections: [Connection]) -> [SacredRing: [Connection]] {
        var buckets: [SacredRing: [Connection]] = [
            .inner: [], .middle: [], .outer: [],
        ]
        for conn in connections {
            let ring = SacredRing.ring(forCircles: conn.circles)
            buckets[ring, default: []].append(conn)
        }
        return buckets
    }
}
