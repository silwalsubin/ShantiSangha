import SwiftUI

/// Full calendar view for browsing goals by date.
/// Navigated to from MilestoneSummaryView via calendar toolbar button.
struct GoalCalendarBrowseView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var navigateToDate: Date?
    @State private var showDateGoals = false

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                fullMonthCalendar
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.08)))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Calendar")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDateGoals) {
            DateGoalsView(vm: vm, date: navigateToDate ?? today)
        }
    }

    // MARK: - Full month calendar

    private var fullMonthCalendar: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button { navigateMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                Text(monthYearLabel(for: displayedMonth))
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)

                Spacer()

                Button { navigateMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 4)

            // Day labels
            dayOfWeekHeaders

            // Month grid
            let days = datesForMonth(displayedMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    if date == .distantPast {
                        Color.clear.frame(height: 40)
                    } else {
                        dateCell(date)
                    }
                }
            }
        }
    }

    // MARK: - Date cell

    private func dateCell(_ date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let dayNum = calendar.component(.day, from: date)
        let goalsOnDate = goalsCount(for: date)

        return Button {
            navigateToDate = date
            showDateGoals = true
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if isToday {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.sacredGold, .sacredGoldDark],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }

                    Text("\(dayNum)")
                        .font(.system(size: 15, weight: isToday ? .semibold : .regular, design: .serif))
                        .foregroundColor(
                            isToday ? .white :
                            date < today ? .sacredText.opacity(0.3) :
                            .sacredText
                        )
                }
                .frame(width: 36, height: 36)

                if goalsOnDate > 0 {
                    Text("\(goalsOnDate)")
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .foregroundColor(isToday ? .white : .sacredGold)
                        .frame(width: 14, height: 14)
                        .background(
                            Circle().fill(isToday ? Color.sacredGoldDark : Color.sacredGold.opacity(0.15))
                        )
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day of week headers

    private var dayOfWeekHeaders: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.sacredSectionLabel)
                    .tracking(1)
                    .foregroundColor(.sacredMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
            }
        }
    }

    // MARK: - Helpers

    private func monthYearLabel(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df.string(from: date)
    }

    private func datesForMonth(_ monthDate: Date) -> [Date] {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        let firstOfMonth = calendar.date(from: comps)!
        let startWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count

        var dates: [Date] = []
        for _ in 0..<(startWeekday - 1) {
            dates.append(.distantPast)
        }
        for d in 0..<daysInMonth {
            dates.append(calendar.date(byAdding: .day, value: d, to: firstOfMonth)!)
        }
        return dates
    }

    private func navigateMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth)!
        }
    }

    private func goalsCount(for date: Date) -> Int {
        let targetDate = calendar.startOfDay(for: date)
        return vm.allMilestones.filter { task in
            guard let daysRemaining = task.daysRemaining else { return false }
            let dueDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysRemaining, to: today)!)
            return dueDate == targetDate
        }.count
    }
}
