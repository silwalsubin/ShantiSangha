import SwiftUI

/// Hint card with a small leading SF Symbol on top and a serif italic prompt
/// below. Used as the chat opener when a conversation is empty; suitable for
/// any surface that wants to invite the user with a single line of warm
/// guidance ("Begin once. Let the form follow.").
///
/// Wraps `LuxCard` so the chrome stays consistent with every other card in
/// the app.
struct SacredOpeningCard: View {
    let icon: String
    let prompt: String
    var subtitle: String? = nil

    var body: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredGold)
                Text(prompt)
                    .font(.sacredBody)
                    .italic()
                    .foregroundColor(.sacredText)
                    .lineSpacing(5)
                if let subtitle {
                    Text(subtitle)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
            }
            .padding(SacredSpacing.m)
        }
    }
}
