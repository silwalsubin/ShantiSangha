import SwiftUI

/// Timeline rail view for milestones — vertical line with dots marking due dates
struct MilestoneTimelineView: View {
    let milestones: [AppTask]
    let onDone: (String) -> Void
    let onSkip: (String) -> Void
    let onDelete: (String) -> Void
    let onProgressUpdate: (String, Int) -> Void
    let onDueDateUpdate: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UPCOMING")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
                .padding(.bottom, 12)

            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                let isOverdue = (milestone.daysRemaining ?? 1) <= 0
                let isLast = index == milestones.count - 1

                HStack(alignment: .top, spacing: 12) {
                    // Timeline rail
                    VStack(spacing: 0) {
                        // Dot
                        Circle()
                            .fill(isOverdue ? Color.sacredRed : Color.sacredGold)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(isOverdue ? Color.sacredRed.opacity(0.3) : Color.sacredGold.opacity(0.3), lineWidth: 3)
                            )

                        // Line
                        if !isLast {
                            Rectangle()
                                .fill(Color.sacredMuted.opacity(0.2))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 16)

                    // Card
                    milestoneCard(milestone, isOverdue: isOverdue)
                        .padding(.bottom, isLast ? 0 : 12)
                }
            }
        }
    }

    private func milestoneCard(_ task: AppTask, isOverdue: Bool) -> some View {
        NavigationLink(destination: GoalDetailView(goalId: task.id)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.title)
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredText)
                        .lineLimit(2)

                    Spacer()

                    // Due label
                    if let days = task.daysRemaining {
                        Text(dueLabel(days))
                            .font(.sacredSmallSemibold)
                            .foregroundColor(isOverdue ? .sacredRed : .sacredGold)
                    }

                    // Menu
                    Menu {
                        Button { onDone(task.id) } label: {
                            Label("Mark complete", systemImage: "checkmark.circle")
                        }
                        Button { onSkip(task.id) } label: {
                            Label("Skip for today", systemImage: "forward.fill")
                        }
                        Button { onDelete(task.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.sacredText)
                            .foregroundColor(.sacredMuted)
                            .frame(width: 28, height: 28)
                    }
                }

                // Progress bar (only if progress > 0)
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

    private func dueLabel(_ days: Int) -> String {
        if days < 0 { return "\(abs(days))d over" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "\(days)d"
    }
}
