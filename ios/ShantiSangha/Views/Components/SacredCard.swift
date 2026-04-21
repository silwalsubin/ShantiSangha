import SwiftUI

/// Standard section card: uppercase label on top, content below, parchment
/// background with a hair-thin gold stroke. Replaces the ad-hoc
/// `card(title:) { ... }` helpers that used to live inside VedicChartView
/// and PlanetDetailView.
///
/// Pass `title: nil` for a card without a header (rare — usually pair the
/// card with a section label). `accent` overrides the stroke color; default
/// is the warm gold used across chart surfaces.
struct SacredCard<Content: View>: View {
    let title: String?
    let accent: Color
    let content: () -> Content

    init(
        _ title: String? = nil,
        accent: Color = .sacredGold.opacity(0.08),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.sacredSectionLabel)
                    .tracking(3)
                    .foregroundColor(.sacredLabel)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sacredBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent, lineWidth: 1))
    }
}
