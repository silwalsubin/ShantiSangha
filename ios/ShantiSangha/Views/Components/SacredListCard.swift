import SwiftUI

/// Grouped-list container — wraps `LuxCard` so every list card across the
/// app shares the same parchment + gold-gradient chrome. Used as the wrapper
/// around timeline groups in Reflect, the profile menu, the "Begin
/// reflection" sheet, and any other vertically grouped row stack.
///
/// `SacredListCard` does NOT impose internal padding — the rows decide their
/// own rhythm so dividers can flush to the card edges.
struct SacredListCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        LuxCard {
            content()
        }
    }
}
