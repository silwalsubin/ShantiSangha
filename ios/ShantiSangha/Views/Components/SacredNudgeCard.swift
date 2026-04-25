import SwiftUI

/// Quiet advisory card — a small leading icon and a single line of gentle
/// copy. Used for the evening nudge on Home; intended for any future "soft
/// hint" surface that is informational, not actionable.
///
/// Wraps `LuxCard` so it shares the same chrome as every other card.
struct SacredNudgeCard: View {
    let icon: String
    let message: String

    var body: some View {
        LuxCard {
            HStack(alignment: .top, spacing: SacredSpacing.s) {
                Image(systemName: icon)
                    .font(.sacredIcon)
                    .foregroundColor(.sacredGold)
                    .padding(.top, 2)

                Text(message)
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
