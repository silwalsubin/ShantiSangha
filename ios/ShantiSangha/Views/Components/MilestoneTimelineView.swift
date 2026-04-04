import SwiftUI

/// Commitment section on home — header with progress ring + task rows
struct MilestoneTimelineView: View {
    let milestones: [AppTask]
    let onDone: (String) -> Void
    let onSkip: (String) -> Void
    let onDelete: (String) -> Void
    let onProgressUpdate: (String, Int) -> Void
    let onDueDateUpdate: (String, String) -> Void

    var onShowAll: (() -> Void)?
    @Binding var filter: CommitmentFilter
    var totalMilestones: Int = 0
    var doneMilestones: Int = 0
    var hasOverdue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon — line — ring
            Button { onShowAll?() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18))
                        .foregroundColor(.sacredGold)
                    Rectangle()
                        .fill(Color.sacredMuted.opacity(0.15))
                        .frame(height: 1)
                    if totalMilestones > 0 {
                        commitmentRing
                    }
                }
            }

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
            .padding(.top, 10)
            .padding(.bottom, 12)

            if milestones.isEmpty {
                Text("Nothing due within this window.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(milestones) { task in
                        TaskRow(
                            task: task,
                            onDone: { onDone(task.id) },
                            onSkip: { onSkip(task.id) },
                            onUndo: {},
                            onDelete: { onDelete(task.id) },
                            onProgressUpdate: { val in onProgressUpdate(task.id, val) },
                            onDueDateUpdate: { date in onDueDateUpdate(task.id, date) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Commitment progress ring

    private var commitmentRing: some View {
        let progress = totalMilestones > 0 ? Double(doneMilestones) / Double(totalMilestones) : 0
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
                Text("\(doneMilestones)")
                    .font(.sacredTextSemibold)
                    .foregroundColor(ringColor)
                Text("of \(totalMilestones)")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
        }
        .frame(width: 48, height: 48)
    }
}
