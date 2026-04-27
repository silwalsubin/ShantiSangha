import Foundation

/// Single source of truth for which connections live on which orbital
/// ring. Originally lived inside the now-deleted `CircleMandalaView`;
/// extracted so the solar system view + any future visualization share
/// the same closeness taxonomy.
enum SacredRing: Int, CaseIterable {
    case inner = 0   // family
    case middle      // close
    case outer       // broader

    static func ring(for type: ConnectionType) -> SacredRing {
        switch type {
        case .spouse, .parent, .child: return .inner
        case .sibling, .friend:        return .middle
        case .colleague, .other:       return .outer
        }
    }

    static func ring(forRawType raw: String) -> SacredRing {
        let type = ConnectionType(rawValue: raw.lowercased()) ?? .other
        return ring(for: type)
    }

    var label: String {
        switch self {
        case .inner:  return "FAMILY"
        case .middle: return "CLOSE"
        case .outer:  return "BROADER"
        }
    }

    /// Orbital radius in meters (RealityKit world units).
    var orbitRadius: Float {
        switch self {
        case .inner:  return 0.95
        case .middle: return 1.65
        case .outer:  return 2.45
        }
    }

    /// Planet sphere radius in meters. Inner rings get larger spheres
    /// so the closeness hierarchy reads at a glance from any camera.
    var planetRadius: Float {
        switch self {
        case .inner:  return 0.105
        case .middle: return 0.090
        case .outer:  return 0.078
        }
    }

    /// Slight orbital inclination per ring so the system reads as 3D
    /// from the start instead of looking flat. Values in radians.
    var inclination: Float {
        switch self {
        case .inner:  return 0.05
        case .middle: return 0.10
        case .outer:  return 0.16
        }
    }

    /// Angular speed in radians per second. Inner rings orbit faster
    /// (Kepler-ish — closer bodies orbit quicker). Tuned for a calm
    /// cadence: full inner orbit ~16s, full outer orbit ~55s. Slow
    /// enough to feel meditative, fast enough that motion is obvious
    /// within a glance.
    var angularSpeed: Float {
        switch self {
        case .inner:  return 0.40
        case .middle: return 0.22
        case .outer:  return 0.11
        }
    }
}

enum RingAssignment {
    /// Bucket connections by ring, preserving the caller's input order.
    /// The visualization layer decides display sort (recency, unread,
    /// alphabetical) — this just routes by relationship type.
    static func bucket(_ connections: [Connection]) -> [SacredRing: [Connection]] {
        var buckets: [SacredRing: [Connection]] = [
            .inner: [], .middle: [], .outer: []
        ]
        for conn in connections {
            let ring = SacredRing.ring(forRawType: conn.relationType)
            buckets[ring, default: []].append(conn)
        }
        return buckets
    }
}
