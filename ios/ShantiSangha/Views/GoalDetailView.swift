import SwiftUI

/// Goal detail — mirrors frontend/src/pages/app/goal-detail.vue
struct GoalDetailView: View {
    let goalId: String
    @State private var goal: Goal?
    @State private var history: [CheckIn] = []
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: goal.type == .recurring ? "arrow.triangle.2.circlepath" : "target")
                                .foregroundColor(.sacredGold)
                            Text(goal.type == .recurring ? "DAILY PRACTICE" : "MILESTONE")
                                .font(.sacredSectionLabel)
                                .tracking(3)
                                .foregroundColor(.sacredLabel)
                        }
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
                                statCard(value: goal.completedAt != nil ? "Done" : "\(days)", label: goal.completedAt != nil ? "Completed" : "Days Left")
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

                    // History
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HISTORY")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)

                        if history.isEmpty {
                            Text("No check-ins yet.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                        } else {
                            ForEach(history) { checkin in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(checkin.completed ? Color.sacredGreen : Color.sacredMuted.opacity(0.2))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Image(systemName: checkin.completed ? "checkmark" : "forward.fill")
                                                .font(.sacredSmall)
                                                .foregroundColor(checkin.completed ? .white : .sacredMutedLight)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formatDate(checkin.date))
                                            .font(.sacredSmallMedium)
                                            .foregroundColor(.sacredText)
                                        if let note = checkin.note, !note.isEmpty {
                                            Text(note)
                                                .font(.sacredSmall)
                                                .foregroundColor(.sacredTextSecondary)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.08)))
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.12)))

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
            history = try await api.get("/goals/\(goalId)/history")
        } catch {
            print("Failed to load goal: \(error)")
        }
        loading = false
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
}
