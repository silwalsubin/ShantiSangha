import SwiftUI

/// A SacredDateStamp paired with a label. Used by the Connection
/// profile's "Important Dates" list and anywhere else a date deserves
/// a name (anniversary, birthday, "day we met"). Mirrors the visual
/// rhythm of a goal row in the Goals tab — same tile, same horizontal
/// padding — so the two screens feel like one app.
///
/// `onTap` makes the whole row a tap target (typically opens an edit
/// sheet). When nil the row is presentational. Trailing slot is for an
/// optional accessory (chevron, delete button, etc).
struct SacredDateRow<Trailing: View>: View {
    let date: Date
    let label: String
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let content = HStack(spacing: 12) {
            SacredDateStamp(date: date)

            Text(label)
                .font(.sacredTextMedium)
                .foregroundColor(.sacredText)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

extension SacredDateRow where Trailing == EmptyView {
    init(date: Date, label: String, onTap: (() -> Void)? = nil) {
        self.date = date
        self.label = label
        self.onTap = onTap
        self.trailing = { EmptyView() }
    }
}
