import SwiftUI

/// Single source of truth for the circular chrome shared by every sacred
/// toolbar circle (profile avatar, notification bell, and future ones).
///
/// What it does, in order:
///   1. Clips the receiver to a circle
///   2. Overlays a hairline gold stroke (ring) at the rim
///   3. Applies a warm drop shadow that lifts the circle off the
///      backdrop — same elevation as the avatar
///
/// The caller sizes themselves with `.frame(...)` first; this modifier is
/// geometry-agnostic so it works for the 36pt toolbar chip, 80pt sheet
/// header, 120pt onboarding preview, etc. If the chip's gold ring or
/// shadow ever needs tweaking, this is the only place to change.
extension View {
    func sacredCircularChrome(
        borderOpacity: Double = 0.42,
        borderWidth: CGFloat = 2,
        shadow: Bool = true
    ) -> some View {
        clipShape(Circle())
            .overlay(Circle().stroke(Color.sacredGold.opacity(borderOpacity), lineWidth: borderWidth))
            .modifier(SacredCircularShadow(active: shadow))
    }
}

private struct SacredCircularShadow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 5)
        } else {
            content
        }
    }
}
