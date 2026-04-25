import SwiftUI

/// Luxe parchment card with a soft gold gradient, hairline gold stroke, and
/// warm lifted shadow — the shared chrome for every card in the app.
///
/// Two ways to use it:
///
/// 1. **As a container** — wrap content that doesn't already have a
///    background/stroke of its own:
///    ```swift
///    LuxCard {
///        VStack { ... }
///            .padding(SacredSpacing.m)
///    }
///    ```
///
/// 2. **As a modifier** (`.luxCardChrome()`) — drop-in replacement when
///    inline content already lays itself out with its own padding and you
///    just want the card chrome on top:
///    ```swift
///    HStack { ... }
///        .padding(14)
///        .luxCardChrome()
///    ```
///
/// `LuxCard` does NOT impose internal padding on its container form — apply
/// your own `.padding(...)` inside the closure so each caller can choose
/// their own rhythm.
struct LuxCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .luxCardChrome()
    }
}

extension View {
    /// Applies the same chrome `LuxCard` uses (parchment fill, gold-gradient
    /// highlight, hairline gold stroke, warm shadow at `SacredRadius.lux`)
    /// directly to the receiver. Use when the content already lays itself
    /// out and you just want it wrapped in card chrome — replaces the older
    /// `.background(RoundedRectangle ...).overlay(stroke)` pattern.
    func luxCardChrome() -> some View {
        background(
            RoundedRectangle(cornerRadius: SacredRadius.lux)
                .fill(Color.sacredBgCard.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: SacredRadius.lux)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.sacredGoldShine.opacity(0.1),
                                    Color.clear,
                                    Color.sacredGoldDark.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SacredRadius.lux)
                .stroke(Color.sacredGold.opacity(0.12), lineWidth: 1)
        )
        .sacredCardShadow()
    }
}
