import SwiftUI

/// A card that displays the daily AI-generated reflection on the Home tab.
/// No title, no label by default — the card just speaks. When a `caption`
/// is provided (e.g. the user is seeing yesterday's reflection while today's
/// is still composing), a small uppercase label appears above the text.
struct ReflectionCardView: View {
    let content: String
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            if let caption {
                Text(caption)
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .tracking(2)
                    .foregroundColor(.sacredLabel)
            }
            Text(content)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.sacredBgCard.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
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
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.sacredGold.opacity(0.12), lineWidth: 1))
        .shadow(color: .sacredMuted.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, 16)
    }
}
