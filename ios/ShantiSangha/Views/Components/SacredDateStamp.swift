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
    /// Optional app-relative state for reminder rows. `nil` keeps the
    /// neutral stamp used by headers and profile date lists.
    var daysRemaining: Int? = nil

    var body: some View {
        let day = Calendar.current.component(.day, from: date)
        let month: String = formatted(date, "MMM")
        VStack(spacing: size * 0.02) {
            Text(month)
                .font(.system(size: size * 0.18, weight: .bold, design: .serif))
                .tracking(1)
                .foregroundColor(monthColor)
            Text("\(day)")
                .font(.system(size: size * 0.36, weight: .semibold, design: .serif))
                .foregroundColor(dayColor)
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .stroke(strokeColor, lineWidth: 1)
                )
        )
        .shadow(color: shadowColor, radius: isToday ? 8 : 0, y: isToday ? 3 : 0)
    }

    private func formatted(_ date: Date, _ pattern: String) -> String {
        let df = DateFormatter()
        df.dateFormat = pattern
        return df.string(from: date).uppercased()
    }

    private var isPast: Bool {
        guard let daysRemaining else { return false }
        return daysRemaining < 0
    }

    private var isToday: Bool {
        daysRemaining == 0
    }

    private var monthColor: Color {
        if isPast { return .sacredMuted.opacity(0.62) }
        if isToday { return .sacredLabel }
        return .sacredMuted
    }

    private var dayColor: Color {
        if isPast { return .sacredMuted }
        if isToday { return .sacredGold }
        return .sacredText
    }

    private var backgroundColor: Color {
        if isPast { return .sacredBgCard.opacity(0.56) }
        if isToday { return .sacredGold.opacity(0.12) }
        return .sacredBgCard
    }

    private var strokeColor: Color {
        if isPast { return .sacredRed.opacity(0.16) }
        if isToday { return .sacredGold.opacity(0.22) }
        return .clear
    }

    private var shadowColor: Color {
        isToday ? .sacredGold.opacity(0.14) : .clear
    }
}
