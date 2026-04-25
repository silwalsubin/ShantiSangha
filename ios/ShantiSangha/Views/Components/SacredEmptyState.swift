import SwiftUI

/// Warm empty-state block — large muted icon, headline, optional subtitle,
/// optional gold pill CTA. Centralized so every "nothing here yet" surface
/// reads the same way: never as a dead end, always with a single next step.
struct SacredEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.sacredHero)
                .foregroundColor(.sacredMutedLight)
            Text(title)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                SacredPrimaryButton(actionLabel, action: action)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
