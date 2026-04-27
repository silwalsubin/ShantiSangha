import Foundation

/// Closeness classification for connections — three concentric "rings":
/// inner = family, middle = close, outer = broader. Originally part of
/// the RealityKit solar system; the SpriteKit view reuses the same
/// taxonomy.
enum SacredRing: Int, CaseIterable {
    case inner = 0
    case middle
    case outer

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
            let ring = SacredRing.ring(forRawType: conn.relationType)
            buckets[ring, default: []].append(conn)
        }
        return buckets
    }
}
