import SwiftUI

/// Shows all goals for a specific date with the ability to add new ones.
/// Navigated to from MilestoneSummaryView when tapping a date.
struct DateGoalsView: View {
    @ObservedObject var vm: HomeViewModel
    let date: Date
    @State private var showNewTask = false

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    private var isToday: Bool { calendar.isDate(date, inSameDayAs: today) }
    private var isPast: Bool { date < today }
    private var isFuture: Bool { date > today }

    // MARK: - Filtering

    private var goalsForDate: [AppTask] {
        vm.allMilestones.filter { task in
            guard let daysRemaining = task.daysRemaining else { return false }
            let dueDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysRemaining, to: today)!)
            return dueDate == date
        }
    }

    private var pendingGoals: [AppTask] {
        goalsForDate.filter { $0.completedAt == nil }
    }

    private var completedGoals: [AppTask] {
        goalsForDate.filter { $0.completedAt != nil }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Date header
                dateHeader
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                // Goals
                if pendingGoals.isEmpty && completedGoals.isEmpty {
                    emptyState
                } else {
                    if !pendingGoals.isEmpty {
                        sectionLabel("ACTIVE")
                        taskList(pendingGoals)
                    }

                    if !completedGoals.isEmpty {
                        sectionLabel("DONE")
                        taskList(completedGoals)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .navigationDestination(isPresented: $showNewTask) {
            NewTaskView { title, type, targetDate in
                await vm.createTask(title: title, type: type, targetDate: targetDate)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(isToday ? "Nothing due today" : isFuture ? "Nothing scheduled" : "Nothing was due")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)

            Button {
                showNewTask = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.sacredSmall)
                    Text("Add a goal")
                        .font(.sacredSmallMedium)
                }
                .foregroundColor(.sacredGold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.sacredGold.opacity(0.1))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.sacredGold.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Date header

    private var dateHeader: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(dayOfWeekShort)
                    .font(.sacredSectionLabel)
                    .tracking(2)
                    .foregroundColor(.sacredMuted)
                Text("\(calendar.component(.day, from: date))")
                    .font(.sacredDisplayNumber)
                    .foregroundColor(isToday ? .sacredGold : .sacredText)
            }
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isToday ? Color.sacredGold.opacity(0.1) : Color.sacredBgCard)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(fullDateLabel)
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)

                Text(summaryLabel)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        if isToday { return "Today" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private var dayOfWeekShort: String {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df.string(from: date).uppercased()
    }

    private var fullDateLabel: String {
        if isToday { return "Today" }
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        return df.string(from: date)
    }

    private var summaryLabel: String {
        let total = goalsForDate.count
        let done = completedGoals.count
        if total == 0 { return "No goals" }
        if done == total { return "All \(total) completed" }
        return "\(total - done) pending, \(done) done"
    }

    // MARK: - Section label & task list

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.sacredSectionLabel)
            .tracking(3)
            .foregroundColor(label == "OVERDUE" ? .sacredRed : .sacredLabel)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

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
