import SwiftUI

/// Shows all recurring tasks for today — pending, completed, and skipped
struct RecurringSummaryView: View {
    @ObservedObject var vm: HomeViewModel

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
                // Progress header
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(.sacredGold)
                    Rectangle()
                        .fill(Color.sacredMuted.opacity(0.15))
                        .frame(height: 1)
                    progressRing
                }
                .padding(.top, 24)

                Text("\(vm.doneRecurring) of \(vm.totalRecurring) complete")
                    .font(.sacredTitle)
                    .foregroundColor(.sacredText)
                    .padding(.top, 8)

                // Pending
                if !pending.isEmpty {
                    sectionLabel("PENDING")
                    taskList(pending)
                }

                // Completed
                if !completed.isEmpty {
                    sectionLabel("COMPLETED")
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressRing: some View {
        let total = vm.totalRecurring
        let done = vm.doneRecurring
        let progress = total > 0 ? Double(done) / Double(total) : 0

        return ZStack {
            Circle()
                .stroke(Color.sacredMuted.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient.sacredGoldShiny,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(done)")
                    .font(.sacredHeading)
                    .foregroundColor(.sacredGold)
                Text("of \(total)")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
        }
        .frame(width: 64, height: 64)
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
        VStack(spacing: 8) {
            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    onDone: { Task { await vm.checkIn(id: task.id, completed: true) } },
                    onSkip: { Task { await vm.checkIn(id: task.id, completed: false) } },
                    onUndo: { Task { await vm.undoCheckIn(id: task.id) } },
                    onDelete: { Task { await vm.deleteTask(id: task.id) } },
                    onProgressUpdate: { _ in },
                    neutralStyle: true
                )
            }
        }
    }
}
