import SwiftUI

/// Calendar-based goals overview. Tapping a date navigates to DateGoalsView.
/// Compact date strip expands into full month grid.
struct MilestoneSummaryView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var navigateToDate: Date?
    @State private var showDateGoals = false
    @State private var expanded = false
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    // MARK: - Grouped goals by date

    /// Groups pending goals (due today + overdue) by their due date, sorted earliest first
    private var groupedGoals: [(date: Date, label: String, tasks: [AppTask])] {
        let pending = vm.allMilestones.filter { task in
            guard task.completedAt == nil else { return false }
            guard let daysRemaining = task.daysRemaining else { return false }
            return daysRemaining <= 0
        }

        // Group by due date
        var grouped: [Date: [AppTask]] = [:]
        for task in pending {
            let days = task.daysRemaining ?? 0
            let dueDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: today)!)
            grouped[dueDate, default: []].append(task)
        }

        return grouped.keys.sorted().map { date in
            let label: String
            if calendar.isDate(date, inSameDayAs: today) {
                label = "Today"
            } else {
                let df = DateFormatter()
                df.dateFormat = "EEEE, MMM d"
                label = df.string(from: date)
            }
            return (date: date, label: label, tasks: grouped[date]!)
        }
    }

    // All overdue items (flat list, sorted by most overdue first)
    private var overdueGoals: [AppTask] {
        vm.allMilestones.filter { $0.completedAt == nil && ($0.daysRemaining ?? 1) < 0 }
            .sorted { ($0.daysRemaining ?? 0) < ($1.daysRemaining ?? 0) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Calendar
                calendarSection
                    .padding(.top, 12)

                // Today group — always shown
                dateGroupHeader("Due today", date: today)
                if let todayGroup = groupedGoals.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
                    taskList(todayGroup.tasks)
                } else {
                    Text("You're all clear today")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredGreen)
                        .padding(.leading, 46)
                        .padding(.bottom, 4)
                }

                // Overdue section — grouped by date with date headers
                let overdueGroups = groupedGoals.filter { !calendar.isDate($0.date, inSameDayAs: today) }
                if !overdueGroups.isEmpty {
                    overdueSectionHeader
                    ForEach(overdueGroups, id: \.date) { group in
                        dateGroupHeader(group.label, date: group.date)
                        taskList(group.tasks)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Goals")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDateGoals) {
            DateGoalsView(vm: vm, date: navigateToDate ?? today)
        }
    }

    // MARK: - Overdue section header

    private var overdueSectionHeader: some View {
        HStack(spacing: 8) {
            Text("CARRIED OVER")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredMuted)

            Spacer()
        }
        .padding(.top, 28)
        .padding(.bottom, 0)
    }

    // MARK: - Calendar section

    private var calendarSection: some View {
        VStack(spacing: 0) {
            if expanded {
                fullMonthCalendar
            } else {
                compactDateStrip
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.08)))
    }

    // MARK: - Compact date strip

    private var compactDateStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Text(monthYearLabel(for: today))
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        displayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
                        expanded = true
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            dayOfWeekHeaders
                .padding(.horizontal, 8)

            let weekDates = datesForWeek(containing: today)
            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    dateCell(date)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Full month calendar

    private var fullMonthCalendar: some View {
        VStack(spacing: 8) {
            HStack {
                Button { navigateMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { expanded = false }
                } label: {
                    HStack(spacing: 6) {
                        Text(monthYearLabel(for: displayedMonth))
                            .font(.sacredTextMedium)
                            .foregroundColor(.sacredText)
                        Image(systemName: "chevron.up")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }

                Spacer()

                Button { navigateMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 4)

            dayOfWeekHeaders
                .padding(.horizontal, 8)

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
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
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
            VStack(spacing: 2) {
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
                            date > today ? .sacredText.opacity(0.3) :
                            .sacredText
                        )
                }
                .frame(width: 36, height: 36)

                // Goal count badge
                if goalsOnDate > 0 {
                    Text("\(goalsOnDate)")
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .foregroundColor(.sacredGold)
                        .frame(height: 10)
                } else {
                    Color.clear.frame(height: 10)
                }
            }
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

    private func datesForWeek(containing date: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: date)
        let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: date)!
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: startOfWeek)! }
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

    // MARK: - Date group header & task list

    private func dateGroupHeader(_ label: String, date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let dayNum = calendar.component(.day, from: date)
        let monthAbbr: String = {
            let df = DateFormatter()
            df.dateFormat = "MMM"
            return df.string(from: date).uppercased()
        }()
        let daysAgo = calendar.dateComponents([.day], from: date, to: today).day ?? 0
        let subtitle: String = {
            if isToday { return "Today" }
            if daysAgo == 1 { return "1 day ago" }
            return "\(daysAgo) days ago"
        }()

        return HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(monthAbbr)
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .tracking(1)
                    .foregroundColor(.sacredMuted)
                Text("\(dayNum)")
                    .font(.sacredTextSemibold)
                    .foregroundColor(isToday ? .sacredGold : .sacredText)
            }
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isToday ? Color.sacredGold.opacity(0.1) : Color.sacredBgCard)
            )

            Text(subtitle)
                .font(.sacredSmallMedium)
                .foregroundColor(isToday ? .sacredGold : .sacredTextSecondary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, design: .serif))
                .foregroundColor(.sacredMuted.opacity(0.5))
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            navigateToDate = date
            showDateGoals = true
        }
    }

    private func taskList(_ tasks: [AppTask], hideDueDate: Bool = true) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRow(
                    task: task,
                    onDone: { Task { await vm.checkIn(id: task.id, completed: true) } },
                    onSkip: { Task { await vm.checkIn(id: task.id, completed: false) } },
                    onUndo: { Task { await vm.undoCheckIn(id: task.id) } },
                    onDelete: { Task { await vm.deleteTask(id: task.id) } },
                    onProgressUpdate: { val in Task { await vm.updateProgress(id: task.id, value: val) } },
                    onDueDateUpdate: { date in Task { await vm.updateDueDate(id: task.id, date: date) } },
                    hideDueDate: hideDueDate
                )

                if index < tasks.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 16)
                }
            }
        }
    }
}
