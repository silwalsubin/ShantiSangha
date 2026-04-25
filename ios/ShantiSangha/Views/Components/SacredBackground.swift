import SwiftUI

/// Page-wide warm parchment background with two soft gold radial highlights.
/// Apply this behind any sacred screen so every tab shares the same warmth
/// instead of falling back to the default system background.
///
/// Usage:
/// ```swift
/// // As a view, inside a ZStack:
/// ZStack {
///     SacredBackground()
///         .ignoresSafeArea()
///     content
/// }
///
/// // Or as a modifier (preferred — drop-in replacement for
/// // `.background(Color.sacredBg.ignoresSafeArea())`):
/// content.sacredBackground()
/// ```
struct SacredBackground: View {
    var body: some View {
        ZStack {
            Color.sacredBg

            LinearGradient(
                colors: [
                    Color.sacredGoldShine.opacity(0.16),
                    Color.sacredBg.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )

            RadialGradient(
                colors: [
                    Color.sacredGold.opacity(0.11),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 260
            )

            RadialGradient(
                colors: [
                    Color.sacredGoldDark.opacity(0.06),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 280
            )
        }
    }
}

extension View {
    /// Drop-in replacement for `.background(Color.sacredBg.ignoresSafeArea())`.
    /// Applies the warm parchment + soft gold radial highlights behind the
    /// content so every screen shares Home's atmosphere.
    func sacredBackground() -> some View {
        background(SacredBackground().ignoresSafeArea())
    }
}
