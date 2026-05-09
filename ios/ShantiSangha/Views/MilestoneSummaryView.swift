import SwiftUI

/// Goals list — shows today's goals and carried-over items.
/// Calendar is accessible via toolbar button.
struct MilestoneSummaryView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var showCalendar = false
    @State private var showNewTask = false

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    // MARK: - Grouped goals by date

    private var groupedGoals: [(date: Date, tasks: [AppTask])] {
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
            (date: date, tasks: grouped[date]!)
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
                        sectionHeader("TODAY")
                        taskList(todayGroup.tasks)
                    }

                    // Carried over section — flat chronological list, each row carries its own date badge
                    let overdueTasks = groupedGoals
                        .filter { !calendar.isDate($0.date, inSameDayAs: today) }
                        .flatMap { $0.tasks }
                    if !overdueTasks.isEmpty {
                        sectionHeader("CARRIED OVER")
                        taskList(overdueTasks)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .sacredBackground()
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
        .navigationDestination(isPresented: $showCalendar) {
            GoalCalendarBrowseView(vm: vm)
        }
        .navigationDestination(isPresented: $showNewTask) {
            NewTaskView { title, type, targetDate, deeperWhy in
                await vm.createTask(title: title, type: type, targetDate: targetDate, deeperWhy: deeperWhy)
            }
        }
    }

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

    // MARK: - Section header

    private func sectionHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredMuted)
            Spacer()
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
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
                    hideDueDate: true,
                    showDateStamp: true
                )

                if index < tasks.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                        .padding(.trailing, 16)
                }
            }
        }
    }
}
