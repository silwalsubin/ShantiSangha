import SwiftUI

/// Sibling of `PrivateFootnote` for sections whose contents are visible
/// to BOTH parties of a friendship — chat media archive, shared chat
/// history, and any future surface where the data isn't owner-private.
/// Same compact layout as `PrivateFootnote`, but a "two people" glyph
/// + warmer phrasing replaces the lock to signal mutual visibility.
struct SharedFootnote: View {
    let text: String

    init(_ text: String = "Both of you can see this.") {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.sacredGold.opacity(0.55))
            Text(text)
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
        }
        .padding(.horizontal, 4)
    }
}
