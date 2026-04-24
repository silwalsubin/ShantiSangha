import SwiftUI

/// Goals list — shows today's goals and carried-over items.
/// Calendar is accessible via toolbar button.
struct MilestoneSummaryView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var navigateToDate: Date?
    @State private var showDateGoals = false
    @State private var showCalendar = false
    @State private var showNewTask = false

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    // MARK: - Grouped goals by date

    private var groupedGoals: [(date: Date, label: String, tasks: [AppTask])] {
        let pending = vm.allMilestones.filter { task in
            guard task.completedAt == nil else { return false }
            guard let daysRemaining = task.daysRemaining else { return false }
            return daysRemaining <= 0
        }

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

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Check if everything is clear
                if groupedGoals.isEmpty {
                    allClearView
                } else {
                    // Today group
                    if let todayGroup = groupedGoals.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
                        dateGroupHeader("Today", date: today)
                        taskList(todayGroup.tasks)
                    }

                    // Carried over section
                    let overdueGroups = groupedGoals.filter { !calendar.isDate($0.date, inSameDayAs: today) }
                    if !overdueGroups.isEmpty {
                        overdueSectionHeader
                        ForEach(overdueGroups, id: \.date) { group in
                            dateGroupHeader(group.label, date: group.date)
                            taskList(group.tasks)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCalendar = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .navigationDestination(isPresented: $showDateGoals) {
            DateGoalsView(vm: vm, date: navigateToDate ?? today)
        }
        .navigationDestination(isPresented: $showCalendar) {
            GoalCalendarBrowseView(vm: vm)
        }
        .navigationDestination(isPresented: $showNewTask) {
            NewTaskView { title, type, targetDate, deeperWhy in
                await vm.createTask(title: title, type: type, targetDate: targetDate, deeperWhy: deeperWhy)
            }
        }
    }

    // MARK: - Carried over header

    // MARK: - All clear celebration

    private var allClearView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "leaf.fill")
                .font(.system(size: 36))
                .foregroundColor(.sacredGreen)

            Text("You're all clear")
                .font(.sacredHeading)
                .foregroundColor(.sacredText)

            Text("Nothing waiting for you today.\nEnjoy the stillness.")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showNewTask = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add a future goal")
                }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
                .frame(minHeight: 44)
            }

            Spacer().frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Carried over header

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

    // MARK: - Date group header

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

    // MARK: - Task list

    private func taskList(_ tasks: [AppTask]) -> some View {
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
                    hideDueDate: true
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
