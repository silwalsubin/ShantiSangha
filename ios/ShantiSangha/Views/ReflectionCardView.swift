import SwiftUI

/// A card that displays the daily AI-generated reflection on the Home tab.
/// No title, no label — the card just speaks.
struct ReflectionCardView: View {
    let content: String

    var body: some View {
        Text(content)
            .font(.system(size: 15, weight: .regular, design: .serif))
            .italic()
            .foregroundColor(.sacredTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
