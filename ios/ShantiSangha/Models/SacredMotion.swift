import SwiftUI
import UIKit

/// Sacred motion tokens — single source of truth for every spring, ease,
/// and atmospheric loop in the app. Lifted from `NavigationOrb`'s rhythm
/// so any new motion already feels made by the same hand.
///
/// Always reach for `SacredMotion.respecting(_)` at call sites — it gates
/// every animation through `UIAccessibility.isReduceMotionEnabled` and
/// falls back to a short cross-fade.
enum SacredMotion {
    // MARK: - Springs

    /// Hero portal — confident, slightly bouncy. Card-to-detail morphs,
    /// modal entrances, the orb's expand/collapse.
    static let morph: Animation = .spring(response: 0.55, dampingFraction: 0.86)

    /// Selection feedback — tighter than `morph`. Tab selection inside
    /// the orb menu, toggle states.
    static let select: Animation = .spring(response: 0.50, dampingFraction: 0.85)

    /// Sub-component shifts (inner-mark rotations, icon swaps). Crisper
    /// than `morph` so the inner element resolves slightly ahead of the
    /// surrounding chrome.
    static let crisp: Animation = .spring(response: 0.55, dampingFraction: 0.82)

    // MARK: - Eases

    /// Soft cross-fade — opacity-only changes, prompt-hint carousel,
    /// the global Reduce Motion fallback.
    static let veil: Animation = .easeInOut(duration: 0.28)

    /// Default content reveal — used by `.sacredRise`.
    static let rise: Animation = .easeOut(duration: 0.42)

    /// Dismissal — mirrors the Reflect BackToHomeButton easing.
    static let dismiss: Animation = .easeInOut(duration: 0.28)

    // MARK: - Atmospheric loops

    /// Slow breathing pulse — used by the orb halo and any "alive"
    /// element. Single source so everything breathes in rough phase.
    static let breathing: Animation = .easeInOut(duration: 2.2)
        .repeatForever(autoreverses: true)

    /// Slower atmospheric breathing — backdrops, the Home chat-pill
    /// glow. Stays out of the user's focal attention.
    static let ambient: Animation = .easeInOut(duration: 3.2)
        .repeatForever(autoreverses: true)

    /// Twinkle phase for particle stars. Per-particle phase offset is
    /// added at the call site.
    static let twinkle: Animation = .easeInOut(duration: 2.6)
        .repeatForever(autoreverses: true)

    // MARK: - Geometry

    /// Morph destinations adopt this radius so the source card's
    /// geometry tweens into a visually-identical shape.
    static let morphRadius: CGFloat = SacredRadius.lux

    // MARK: - Reduce Motion gate

    @MainActor
    static var prefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Wrap any token at the call site so callers never have to think
    /// about accessibility: `withAnimation(SacredMotion.respecting(.morph)) { ... }`.
    @MainActor
    static func respecting(_ animation: Animation) -> Animation {
        prefersReducedMotion ? veil : animation
    }
}
