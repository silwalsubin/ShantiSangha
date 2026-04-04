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
                    .font(.sacredText)
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
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(recurringGoals) { goal in
                                NavigationLink(destination: GoalDetailView(goalId: goal.id)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(goal.title)
                                                .font(.sacredTextMedium)
                                                .foregroundColor(.sacredText)
                                            Text("Longest: \(goal.longestStreak) days")
                                                .font(.sacredMicro)
                                                .foregroundColor(.sacredLabel)
                                                .textCase(.uppercase)
                                                .tracking(1)
                                        }
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: "flame.fill")
                                                .font(.sacredSmall)
                                                .foregroundColor(.sacredGold)
                                            Text("\(goal.currentStreak)")
                                                .font(.sacredBodyBold)
                                                .foregroundColor(.sacredGold)
                                            Text("days")
                                                .font(.sacredMicro)
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

                    // Commitments
                    sectionCard {
                        sectionLabel(icon: "calendar.badge.clock", text: "COMMITMENTS")

                        if milestoneGoals.isEmpty {
                            Text("No commitments yet. Set one from Home.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(milestoneGoals) { goal in
                                NavigationLink(destination: GoalDetailView(goalId: goal.id)) {
                                    HStack {
                                        Text(goal.title)
                                            .font(.sacredTextMedium)
                                            .foregroundColor(.sacredText)
                                        Spacer()
                                        if let days = goal.daysRemaining {
                                            Text(days > 0 ? "\(days)d left" : days == 0 ? "Today" : "\(abs(days))d over")
                                                .font(days <= 0 ? .sacredSmallSemibold : .sacredSmall)
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
        .refreshable { await loadGoals() }
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
                .font(.sacredSmall)
                .foregroundColor(.sacredGold)
            Text(text)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
        }
    }
}
