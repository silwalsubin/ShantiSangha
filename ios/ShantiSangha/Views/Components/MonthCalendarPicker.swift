import SwiftUI

/// Sacred-styled month calendar used on the Calendar tab and inside the
/// reminder edit page. Caller owns both the displayed month and the
/// selected date via bindings; the picker handles month chevrons and a
/// tap-the-title year picker. Pass `dotCount` when reminder dots should
/// render on tiles (Calendar tab); leave nil for a clean picker view.
struct MonthCalendarPicker: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    var dotCount: ((Date) -> Int)? = nil

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.bottom, 12)
            dayOfWeekHeaders
                .padding(.bottom, 4)
            dateGrid
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.sacredGold)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Menu {
                Button {
                    let today = Date()
                    displayedMonth = today
                    selectedDate = today
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Today", systemImage: "calendar.badge.clock")
                }
                Divider()
                ForEach(yearOptions, id: \.self) { year in
                    Button {
                        jumpToYear(year)
                    } label: {
                        HStack {
                            Text(String(year))
                            if year == calendar.component(.year, from: displayedMonth) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(monthYearLabel(displayedMonth))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundColor(.sacredText)
                    .tracking(0.4)
            }
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.sacredGold)
                    .frame(width: 44, height: 44)
            }
        }
    }

    /// Year picker range — 100 years back to cover any anchor birth year,
    /// 20 forward for future planning. The menu scrolls so length is fine.
    private var yearOptions: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 100)...(currentYear + 20))
    }

    private func changeMonth(_ delta: Int) {
        guard let new = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = new
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func jumpToYear(_ year: Int) {
        let month = calendar.component(.month, from: displayedMonth)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let new = calendar.date(from: components) {
            displayedMonth = new
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Headers + rule

    private var dayOfWeekHeaders: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                        .frame(maxWidth: .infinity)
                }
            }
            MonthCalendarPicker.goldRule
        }
    }

    /// Soft horizontal gold rule that fades to nothing at both edges.
    /// `static` so other views (e.g., CalendarView's detail pane) can
    /// match the picker's underline exactly without copying the gradient.
    static var goldRule: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [
                    Color.sacredGold.opacity(0),
                    Color.sacredGold.opacity(0.25),
                    Color.sacredGold.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, 8)
    }

    // MARK: - Grid

    private var dateGrid: some View {
        let days = datesForMonth(displayedMonth)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 4
        ) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    dateCell(date)
                } else {
                    Color.clear.frame(height: 54)
                }
            }
        }
    }

    private func dateCell(_ date: Date) -> some View {
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDate(date, inSameDayAs: Date())
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let count = dotCount?(date) ?? 0

        return Button {
            selectedDate = date
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.sacredGold, .sacredGoldDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                            .shadow(color: .sacredGold.opacity(0.35), radius: 6)
                    } else if isToday {
                        Circle()
                            .stroke(Color.sacredGold, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                    }
                    Text("\(dayNum)")
                        .font(.system(size: 15,
                                      weight: isSelected ? .semibold : .regular,
                                      design: .serif))
                        .foregroundColor(isSelected
                                         ? .white
                                         : (isToday ? .sacredGold : .sacredText))
                }

                if count > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<min(count, 3), id: \.self) { _ in
                            Circle()
                                .fill(Color.sacredGold)
                                .frame(width: 4, height: 4)
                        }
                        if count > 3 {
                            Text("·")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.sacredGold)
                        }
                    }
                    .frame(height: 4)
                } else {
                    Color.clear.frame(height: 4)
                }
            }
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func monthYearLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    /// Returns the day cells to render for `anchor`'s month in a Sunday-
    /// start grid. Nils represent padding cells before the 1st and after
    /// the last day so the grid always lays out as a clean rectangle.
    private func datesForMonth(_ anchor: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)  // 1 = Sunday
        let leadingPadding = firstWeekday - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leadingPadding)
        for d in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: d, to: firstDay) {
                cells.append(date)
            }
        }
        let trailingPadding = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailingPadding))
        return cells
    }
}
