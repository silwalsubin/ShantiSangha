import SwiftUI

/// 36×36 calendar tile — month abbreviation stacked over day number,
/// rendered in the sacred serif. Originally lived inside TaskRow as the
/// leading slot for one-time goals; now shared so the Connection
/// profile's "Important Dates" rows render with the same visual weight
/// as a goal row.
///
/// `isToday` swaps the day glyph to gold and tints the background — keep
/// it false for past/future dates that are reference-only (anniversaries,
/// birthdays, "day we met").
struct SacredDateStamp: View {
    let date: Date
    var isToday: Bool = false

    var body: some View {
        let day = Calendar.current.component(.day, from: date)
        let month: String = {
            let df = DateFormatter()
            df.dateFormat = "MMM"
            return df.string(from: date).uppercased()
        }()
        VStack(spacing: 0) {
            Text(month)
                .font(.system(size: 8, weight: .bold, design: .serif))
                .tracking(1)
                .foregroundColor(.sacredMuted)
            Text("\(day)")
                .font(.sacredTextSemibold)
                .foregroundColor(isToday ? .sacredGold : .sacredText)
        }
        .frame(width: 36, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color.sacredGold.opacity(0.1) : Color.sacredBgCard)
        )
    }
}
