import SwiftUI

/// A single tappable row inside a list / menu card — leading icon, title,
/// optional subtitle, and a trailing chevron. Used inside `SacredListCard`
/// for surfaces like the profile menu and the "Begin reflection" sheet.
///
/// `SacredMenuRow` does not draw its own divider or background — it expects
/// to live inside a `SacredListCard` (or similar) which provides the
/// container chrome and dividers between rows.
struct SacredMenuRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.sacredGold.opacity(0.75))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
                if let subtitle {
                    Text(subtitle)
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.sacredMuted.opacity(0.5))
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
