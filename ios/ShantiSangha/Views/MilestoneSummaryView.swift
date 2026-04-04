import SwiftUI

/// Shows all milestone tasks — pending (sorted by urgency) and completed
struct MilestoneSummaryView: View {
    @ObservedObject var vm: HomeViewModel

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
                }
                .padding(.top, 24)

                Text("\(vm.doneMilestones) of \(vm.totalMilestones) complete")
                    .font(.sacredTitle)
                    .foregroundColor(.sacredText)
                    .padding(.top, 8)

                // Pending
                if !vm.pendingMilestones.isEmpty {
                    sectionLabel("PENDING")
                    milestoneList(vm.pendingMilestones)
                }

                // Completed
                if !vm.completedMilestones.isEmpty {
                    sectionLabel("COMPLETED")
                    milestoneList(vm.completedMilestones)
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

    private func milestoneList(_ tasks: [AppTask]) -> some View {
        VStack(spacing: 8) {
            ForEach(tasks) { task in
                let isOverdue = (task.daysRemaining ?? 1) <= 0 && !task.checkedIn
                NavigationLink(destination: GoalDetailView(goalId: task.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(task.title)
                                .font(.sacredTextMedium)
                                .foregroundColor(.sacredText)
                                .lineLimit(2)

                            Spacer()

                            if let days = task.daysRemaining, !task.checkedIn {
                                Text(dueLabel(days))
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(isOverdue ? .sacredRed : .sacredGold)
                            }

                            if task.checkedIn {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.sacredGreen)
                            }
                        }

                        // Progress bar
                        if task.progress > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.sacredMuted.opacity(0.15))
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(LinearGradient.sacredGoldShiny)
                                        .frame(width: geo.size.width * CGFloat(task.progress) / 100, height: 5)
                                }
                            }
                            .frame(height: 5)

                            Text("\(task.progress)%")
                                .font(.sacredMicro)
                                .foregroundColor(.sacredMuted)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isOverdue ? Color.sacredRed.opacity(0.06) : Color.sacredBgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isOverdue ? Color.sacredRed.opacity(0.25) : Color.sacredMuted.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dueLabel(_ days: Int) -> String {
        if days < 0 { return "\(abs(days))d over" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "\(days)d left"
    }
}
