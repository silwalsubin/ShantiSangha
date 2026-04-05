import SwiftUI

/// Goal detail — mirrors frontend/src/pages/app/goal-detail.vue
struct GoalDetailView: View {
    let goalId: String
    @State private var goal: Goal?
    @State private var activities: [GoalActivityItem] = []
    @State private var loading = true
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let goal = goal {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: goal.type == .recurring ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                            .font(.sacredTitle)
                            .foregroundColor(.sacredGold)
                        Text(goal.title)
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)
                    }

                    // Stats
                    if goal.type == .recurring {
                        HStack(spacing: 12) {
                            statCard(value: "\(goal.currentStreak ?? 0)", label: "Current Streak")
                            statCard(value: "\(goal.longestStreak ?? 0)", label: "Longest Streak")
                        }
                    } else {
                        HStack(spacing: 12) {
                            if let days = goal.daysRemaining {
                                statCard(
                                    value: goal.completedAt != nil ? "Done" : days < 0 ? "Overdue" : "\(days)",
                                    label: goal.completedAt != nil ? "Completed" : days < 0 ? "\(abs(days))d over" : "Days Left"
                                )
                            }
                            statCard(value: "\(goal.progress ?? 0)%", label: "Progress")
                        }
                    }

                    // Deeper Why
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "leaf")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredGold)
                            Text("THE DEEPER WHY")
                                .font(.sacredSectionLabel)
                                .tracking(3)
                                .foregroundColor(.sacredLabel)
                        }
                        if let why = goal.deeperWhy, !why.isEmpty {
                            Text("\"\(why)\"")
                                .font(.sacredBody)
                                .italic()
                                .foregroundColor(.sacredText)
                        } else {
                            Text("What draws you to this task? Understanding the deeper intention behind your commitments can transform discipline into devotion.")
                                .font(.sacredText)
                                .foregroundColor(.sacredMuted)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.12)))

                    // Activity timeline
                    VStack(alignment: .leading, spacing: 0) {
                        Text("HISTORY")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)
                            .padding(.bottom, 16)

                        if activities.isEmpty {
                            Text("No activity yet.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                        } else {
                            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                                let isLast = index == activities.count - 1

                                HStack(alignment: .top, spacing: 14) {
                                    // Timeline rail
                                    VStack(spacing: 0) {
                                        Circle()
                                            .fill(dotColor(for: activity.action))
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle()
                                                    .stroke(dotColor(for: activity.action).opacity(0.3), lineWidth: 3)
                                            )

                                        if !isLast {
                                            Rectangle()
                                                .fill(Color.sacredMuted.opacity(0.15))
                                                .frame(width: 1.5)
                                                .frame(maxHeight: .infinity)
                                        }
                                    }
                                    .frame(width: 18)

                                    // Content
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(actionLabel(activity.action))
                                                .font(.sacredSmallMedium)
                                                .foregroundColor(.sacredText)
                                            Spacer()
                                            Image(systemName: actionIcon(activity.action))
                                                .font(.sacredMicro)
                                                .foregroundColor(dotColor(for: activity.action))
                                        }
                                        if let detail = activity.detail {
                                            Text(detail)
                                                .font(.sacredSmall)
                                                .foregroundColor(.sacredTextSecondary)
                                        }
                                        Text(formatDateTime(activity.createdAt))
                                            .font(.sacredMicro)
                                            .foregroundColor(.sacredMuted)
                                    }
                                    .padding(.bottom, isLast ? 0 : 20)
                                }
                            }
                        }
                    }

                    Text("Started \(formatDate(goal.createdAt))")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredLabel)
                        .textCase(.uppercase)
                        .tracking(1)
                }
                .padding(16)
            } else {
                Text("Task not found.")
                    .foregroundColor(.sacredTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            goal = try await api.get("/goals/\(goalId)")
            activities = try await api.get("/goals/\(goalId)/history")
        } catch {
            print("Failed to load goal: \(error)")
        }
        loading = false
    }

    // MARK: - Activity helpers

    private func dotColor(for action: String) -> Color {
        switch action {
        case "Completed": return .sacredGreen
        case "Skipped": return .sacredMuted.opacity(0.4)
        case "ProgressUpdated": return .sacredGold
        case "DueDateChanged": return .sacredGold
        case "Created": return .sacredGold
        case "Undone": return .sacredMuted.opacity(0.4)
        default: return .sacredMuted
        }
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "Completed": return "checkmark"
        case "Skipped": return "forward.fill"
        case "ProgressUpdated": return "chart.bar.fill"
        case "DueDateChanged": return "calendar"
        case "Created": return "plus"
        case "Undone": return "arrow.uturn.backward"
        default: return "circle"
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "Completed": return "Completed"
        case "Skipped": return "Skipped"
        case "ProgressUpdated": return "Progress updated"
        case "DueDateChanged": return "Due date changed"
        case "Created": return "Created"
        case "Undone": return "Undone"
        default: return action
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredGold)
            Text(label)
                .font(.sacredSectionLabel)
                .tracking(2)
                .foregroundColor(.sacredMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.08)))
    }

    private func formatDate(_ dateStr: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let date = f.date(from: dateStr.prefix(10).description) {
            f.dateFormat = "MMM d, yyyy"
            return f.string(from: date)
        }
        return dateStr
    }

    private func formatDateTime(_ dateStr: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        if let date = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) {
            let f = DateFormatter()
            f.dateFormat = "MMM d, yyyy 'at' h:mm a"
            return f.string(from: date)
        }
        return dateStr
    }
}
