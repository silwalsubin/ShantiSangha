import SwiftUI

/// Standard section card: optional uppercase label on top, content below.
/// Wraps `LuxCard` so every card in the app shares one chrome (parchment +
/// gold gradient + warm shadow at `SacredRadius.lux`).
struct SacredCard<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(
        _ title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                if let title {
                    Text(title)
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                }
                content()
            }
            .padding(SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
