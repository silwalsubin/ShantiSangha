import SwiftUI

/// Shows all commitment tasks — pending (sorted by urgency) and completed
struct MilestoneSummaryView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var filter: CommitmentFilter = .all

    private var filteredAll: [AppTask] {
        vm.allMilestones.filter { task in
            guard let max = filter.maxDays else { return true }
            return (task.daysRemaining ?? 999) <= max
        }
    }

    private var filteredPending: [AppTask] {
        filteredAll.filter { !$0.checkedIn }
            .sorted { ($0.daysRemaining ?? 999) < ($1.daysRemaining ?? 999) }
    }

    private var filteredCompleted: [AppTask] {
        filteredAll.filter { $0.checkedIn && $0.completedToday == true }
    }

    private var filteredTotal: Int { filteredAll.count }
    private var filteredDone: Int { filteredCompleted.count }
    private var hasOverdue: Bool { filteredPending.contains { ($0.daysRemaining ?? 1) <= 0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18))
                        .foregroundColor(.sacredGold)
                    Rectangle()
                        .fill(Color.sacredMuted.opacity(0.15))
                        .frame(height: 1)
                    commitmentRing
                }
                .padding(.top, 24)

                Text("\(filteredDone) of \(filteredTotal) complete")
                    .font(.sacredTitle)
                    .foregroundColor(.sacredText)
                    .padding(.top, 8)

                // Filter pills
                HStack(spacing: 6) {
                    ForEach(CommitmentFilter.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { filter = option }
                        } label: {
                            Text(option.rawValue)
                                .font(.sacredMicro)
                                .foregroundColor(filter == option ? .sacredGold : .sacredMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(filter == option ? Color.sacredGold.opacity(0.12) : Color.clear)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(filter == option ? Color.sacredGold.opacity(0.3) : Color.sacredMuted.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.top, 12)

                // Pending
                if !filteredPending.isEmpty {
                    sectionLabel("PENDING")
                    taskList(filteredPending)
                }

                // Completed
                if !filteredCompleted.isEmpty {
                    sectionLabel("COMPLETED")
                    taskList(filteredCompleted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                    onProgressUpdate: { val in Task { await vm.updateProgress(id: task.id, value: val) } },
                    onDueDateUpdate: { date in Task { await vm.updateDueDate(id: task.id, date: date) } },
                    neutralStyle: true
                )
            }
        }
    }

    // MARK: - Progress ring

    private var commitmentRing: some View {
        let progress = filteredTotal > 0 ? Double(filteredDone) / Double(filteredTotal) : 0
        let ringColor: Color = hasOverdue ? .sacredRed : .sacredGold
        let gradient = LinearGradient(
            colors: hasOverdue ? [.sacredRed, .sacredRed.opacity(0.7)] : [.sacredGoldShine, .sacredGold],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            Circle()
                .stroke(Color.sacredMuted.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)

            VStack(spacing: 0) {
                Text("\(filteredDone)")
                    .font(.sacredTextSemibold)
                    .foregroundColor(ringColor)
                Text("of \(filteredTotal)")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
        }
        .frame(width: 48, height: 48)
    }
}
