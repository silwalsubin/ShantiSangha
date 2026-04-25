import SwiftUI

/// Soft ghost-style action row — rounded rectangle with a faint parchment
/// fill, gold-tinted icon disc, and serif label. Used for "Add task" on Home
/// and any other "+ create" affordance that should feel quiet rather than
/// shout for attention.
struct SacredGhostRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: SacredSpacing.s) {
                Image(systemName: icon)
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredGold)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.sacredGold.opacity(0.08)))

                Text(label)
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredTextSecondary)

                Spacer()
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.sacredBgCard.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: SacredRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SacredRadius.card)
                    .stroke(Color.sacredGold.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
