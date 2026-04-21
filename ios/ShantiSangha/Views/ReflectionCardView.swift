import SwiftUI

/// A card that displays the daily AI-generated reflection on the Home tab.
/// No title, no label by default — the card just speaks. When a `caption`
/// is provided (e.g. the user is seeing yesterday's reflection while today's
/// is still composing), a small uppercase label appears above the text.
struct ReflectionCardView: View {
    let content: String
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            if let caption {
                Text(caption)
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .tracking(2)
                    .foregroundColor(.sacredLabel)
            }
            Text(content)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.sacredGold.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sacredGold.opacity(0.1)))
        )
        .padding(.horizontal, 16)
    }
}
