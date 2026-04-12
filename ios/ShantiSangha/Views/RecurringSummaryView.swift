import SwiftUI

/// Shows all recurring tasks for today — pending, completed, and skipped
struct RecurringSummaryView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var activeSwipeId: String?

    private var allRecurring: [AppTask] {
        vm.tasks.filter { $0.type == .recurring }
    }

    private var pending: [AppTask] {
        allRecurring.filter { !$0.checkedIn }
    }

    private var completed: [AppTask] {
        allRecurring.filter { $0.checkedIn && $0.completedToday == true }
    }

    private var skipped: [AppTask] {
        allRecurring.filter { $0.checkedIn && $0.completedToday == false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Pending
                if !pending.isEmpty {
                    sectionLabel("ACTIVE")
                    taskList(pending)
                }

                // Completed
                if !completed.isEmpty {
                    sectionLabel("DONE")
                    taskList(completed)
                }

                // Skipped
                if !skipped.isEmpty {
                    sectionLabel("SKIPPED")
                    taskList(skipped)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var progressRing: some View {
        let total = vm.totalRecurring
        let done = vm.doneRecurring
        let progress = total > 0 ? Double(done) / Double(total) : 0

        return ZStack {
            Circle()
                .stroke(Color.sacredMuted.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient.sacredGoldShiny,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(done)/\(total)")
                .font(.sacredMicroBold)
                .foregroundColor(.sacredGold)
        }
        .frame(width: 32, height: 32)
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.sacredSectionLabel)
            .tracking(3)
            .foregroundColor(.sacredLabel)
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
                    onProgressUpdate: { _ in },
                    activeSwipeId: $activeSwipeId
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
