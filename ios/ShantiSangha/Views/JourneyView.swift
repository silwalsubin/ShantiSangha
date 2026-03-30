import SwiftUI

/// Journey — progress tracking. Mirrors frontend/src/pages/app/journey.vue
struct JourneyView: View {
    @State private var goals: [AppTask] = []
    @State private var loading = true
    private let api = ApiService.shared

    var recurringGoals: [AppTask] { goals.filter { $0.type == .recurring } }
    var milestoneGoals: [AppTask] { goals.filter { $0.type == .oneTime } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("See how you're growing over time.")
                    .font(.system(size: 14))
                    .foregroundColor(.sacredTextSecondary)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // Your Dharma
                    sectionCard {
                        sectionLabel(icon: "flame.fill", text: "YOUR DHARMA")

                        if recurringGoals.isEmpty {
                            Text("No tasks yet. Set one from Home.")
                                .font(.system(size: 14))
                                .foregroundColor(.sacredTextSecondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(recurringGoals) { goal in
                                NavigationLink(destination: GoalDetailView(goalId: goal.id)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(goal.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.sacredText)
                                            Text("Longest: \(goal.longestStreak) days")
                                                .font(.system(size: 10))
                                                .foregroundColor(.sacredLabel)
                                                .textCase(.uppercase)
                                                .tracking(1)
                                        }
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.sacredGold)
                                            Text("\(goal.currentStreak)")
                                                .font(.system(size: 14, weight: .bold, design: .serif))
                                                .foregroundColor(.sacredGold)
                                            Text("days")
                                                .font(.system(size: 10))
                                                .foregroundColor(.sacredMuted)
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.1)))
                                }
                            }
                        }
                    }

                    // Milestones
                    sectionCard {
                        sectionLabel(icon: "target", text: "MILESTONES")

                        if milestoneGoals.isEmpty {
                            Text("No milestones yet. Set one from Home.")
                                .font(.system(size: 14))
                                .foregroundColor(.sacredTextSecondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(milestoneGoals) { goal in
                                NavigationLink(destination: GoalDetailView(goalId: goal.id)) {
                                    HStack {
                                        Text(goal.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.sacredText)
                                        Spacer()
                                        if let days = goal.daysRemaining {
                                            Text(days > 0 ? "\(days)d left" : days == 0 ? "Today" : "\(abs(days))d over")
                                                .font(.system(size: 12, weight: days <= 0 ? .bold : .regular, design: .serif))
                                                .foregroundColor(days <= 0 ? .sacredRed : .sacredGold)
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.1)))
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadGoals() }
    }

    private func loadGoals() async {
        do {
            goals = try await api.get("/goals")
        } catch {
            print("Failed to load goals: \(error)")
        }
        loading = false
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.12)))
    }

    private func sectionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.sacredGold)
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .tracking(3)
                .foregroundColor(.sacredLabel)
        }
    }
}
