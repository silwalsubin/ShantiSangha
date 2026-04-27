import Foundation

/// Global motion state read by `OrbitSystem` and `PulseSystem` each
/// frame. The RealityKit ECS systems can't directly read SwiftUI
/// `@Environment` values, so the SwiftUI host (`CircleSolarSystemView`)
/// mirrors `accessibilityReduceMotion` here.
///
/// When `reduceMotion` is true:
///   - Planets stay at their `baseAngle` position (no orbital sweep)
///   - Avatar moons stay at their `baseAngle` (no orbit around planet)
///   - Pulse halos stay at scale 1.0 (no breathing)
///   - Camera reset on double-tap cuts directly instead of springing
///
/// Single static value — there's only ever one solar scene on
/// screen at a time, so a singleton is the simplest model.
@MainActor
enum MotionPreferences {
    static var reduceMotion: Bool = false
}
