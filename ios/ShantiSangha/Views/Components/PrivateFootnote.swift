import SwiftUI

/// Quiet reassurance under any owner-private section — pairs a warm
/// lock with a one-liner like "Only you can see this." Centralizing
/// the pattern means the same gentle treatment shows up everywhere
/// the user has stored something private (notes, dates, keepsakes,
/// future surfaces) without each section reinventing the styling.
///
/// Use sparingly — this is a footnote, not a banner. Place it
/// directly under the section's card with the same horizontal
/// padding so the lock aligns with the section label above.
struct PrivateFootnote: View {
    let text: String

    init(_ text: String = "Only you can see this.") {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.sacredGold.opacity(0.55))
            Text(text)
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
        }
        .padding(.horizontal, 4)
    }
}
