import SwiftUI

/// 36×36 calendar tile — month abbreviation stacked over day number,
/// rendered in the sacred serif. Originally lived inside TaskRow as the
/// leading slot for one-time goals; now shared so the Connection
/// profile's "Important Dates" rows render with the same visual weight
/// as a goal row.
struct SacredDateStamp: View {
    let date: Date
    /// Edge length of the square tile. Fonts scale with `size` so the
    /// large hero stamp in the Home header and the small inline stamp
    /// in reminder rows share the same proportions.
    var size: CGFloat = 40

    var body: some View {
        let day = Calendar.current.component(.day, from: date)
        let month: String = formatted(date, "MMM")
        let weekday: String = formatted(date, "EEE")
        VStack(spacing: 0) {
            Text(month)
                .font(.system(size: size * 0.18, weight: .bold, design: .serif))
                .tracking(1)
                .foregroundColor(.sacredMuted)
            Text("\(day)")
                .font(.system(size: size * 0.36, weight: .semibold, design: .serif))
                .foregroundColor(.sacredText)
            Text(weekday)
                .font(.system(size: size * 0.16, weight: .bold, design: .serif))
                .tracking(1)
                .foregroundColor(.sacredMuted)
        }
        .padding(.vertical, size * 0.10)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color.sacredBgCard)
        )
    }

    private func formatted(_ date: Date, _ pattern: String) -> String {
        let df = DateFormatter()
        df.dateFormat = pattern
        return df.string(from: date).uppercased()
    }
}
