import SwiftUI

/// Journey — "How am I actually doing?"
struct JourneyView: View {
    @State private var journey: JourneyData?
    @State private var reflection: String?
    @State private var loading = true
    @State private var reflectionLoading = false
    @State private var reflectionTimedOut = false
    @State private var selectedPeriod: JourneyPeriod = .lastWeek
    @State private var insights: [InsightItem] = []
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Period selector
                HStack(spacing: 6) {
                    ForEach(JourneyPeriod.allCases, id: \.self) { period in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { selectedPeriod = period }
                            Task { await loadAll() }
                        } label: {
                            Text(period.label)
                                .font(.sacredMicro)
                                .foregroundColor(selectedPeriod == period ? .sacredGold : .sacredMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selectedPeriod == period ? Color.sacredGold.opacity(0.12) : Color.clear)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(selectedPeriod == period ? Color.sacredGold.opacity(0.3) : Color.sacredMuted.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.bottom, 32)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let journey = journey {
                    // Hero ring — overall consistency
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.sacredMuted.opacity(0.1), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: Double(journey.summary.completionRate) / 100)
                                .stroke(
                                    LinearGradient(colors: [.sacredGoldShine, .sacredGold], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.easeOut(duration: 0.8), value: journey.summary.completionRate)

                            VStack(spacing: 2) {
                                Text("\(journey.summary.practicesCompleted)")
                                    .font(.system(size: 36, weight: .bold, design: .serif))
                                    .foregroundColor(.sacredGold)
                                Text("practices")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredMuted)
                            }
                        }
                        .frame(width: 120, height: 120)

                        if journey.summary.completionRate > 0 {
                            Text("\(journey.summary.completionRate)% consistency")
                                .font(.sacredSmallMedium)
                                .foregroundColor(.sacredText)
                        }

                        if journey.summary.commitmentsFinished > 0 {
                            Text("\(journey.summary.commitmentsFinished) commitment\(journey.summary.commitmentsFinished == 1 ? "" : "s") fulfilled")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredGreen)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)

                    // AI Reflection
                    if reflectionLoading && !reflectionTimedOut {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Reflecting...")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)
                        .task {
                            try? await Task.sleep(nanoseconds: 10_000_000_000)
                            if reflectionLoading { reflectionTimedOut = true }
                        }
                    } else if let reflection = reflection {
                        Text(reflection)
                            .font(.sacredBody)
                            .italic()
                            .foregroundColor(.sacredText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 28)
                    }

                    // Practice breakdown
                    if !journey.practices.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(journey.practices.enumerated()), id: \.element.id) { index, practice in
                                NavigationLink {
                                    GoalCalendarView(
                                        goalId: practice.id,
                                        goalTitle: practice.title,
                                        goalCreatedAt: practice.days.first?.date ?? journey.from
                                    )
                                } label: {
                                    HStack(spacing: 14) {
                                        // Mini ring
                                        PracticeRing(
                                            done: practice.daysCompleted,
                                            total: practice.totalDays
                                        )
                                        .frame(width: 40, height: 40)

                                        Text(practice.title)
                                            .font(.sacredTextMedium)
                                            .foregroundColor(.sacredText)

                                        Spacer()

                                        Text("\(practice.daysCompleted)/\(practice.totalDays)")
                                            .font(.sacredSmall)
                                            .foregroundColor(.sacredMuted)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.sacredMuted.opacity(0.5))
                                    }
                                }
                                .padding(.vertical, 12)

                                if index < journey.practices.count - 1 {
                                    Divider()
                                        .padding(.leading, 54)
                                }
                            }
                        }
                        .padding(.bottom, 28)
                    }

                    // Fulfilled commitments
                    if !journey.completedCommitments.isEmpty {
                        Rectangle()
                            .fill(Color.sacredMuted.opacity(0.12))
                            .frame(height: 1)
                            .padding(.bottom, 20)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("FULFILLED")
                                .font(.sacredSectionLabel)
                                .tracking(3)
                                .foregroundColor(.sacredLabel)
                                .padding(.bottom, 12)

                            ForEach(Array(journey.completedCommitments.enumerated()), id: \.element.id) { index, c in
                                HStack(spacing: 12) {
                                    Image(systemName: "leaf.fill")
                                        .font(.sacredSmall)
                                        .foregroundColor(.sacredGreen)
                                    Text(c.title)
                                        .font(.sacredTextMedium)
                                        .foregroundColor(.sacredText)
                                }
                                .padding(.vertical, 10)

                                if index < journey.completedCommitments.count - 1 {
                                    Divider()
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }

                    // Saved insights
                    if !insights.isEmpty {
                        Rectangle()
                            .fill(Color.sacredMuted.opacity(0.12))
                            .frame(height: 1)
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("INSIGHTS")
                                .font(.sacredSectionLabel)
                                .tracking(3)
                                .foregroundColor(.sacredLabel)
                                .padding(.bottom, 16)

                            ForEach(insights) { insight in
                                insightCard(insight)
                                    .padding(.bottom, 12)
                            }
                        }
                    }
                } else {
                    Text("Start your practices to see your journey unfold.")
                        .font(.sacredText)
                        .foregroundColor(.sacredTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .refreshable { await loadAll() }
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
    }

    // MARK: - Insight Card

    private func insightCard(_ insight: InsightItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flame")
                .font(.system(size: 12))
                .foregroundColor(.sacredGold)
                .padding(.top, 3)

            Text(insight.content)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sacredGold.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sacredGold.opacity(0.08)))
        )
        .contextMenu {
            Button {
                Task { await dismissInsight(insight) }
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
            ShareLink(item: insight.content) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func dismissInsight(_ insight: InsightItem) async {
        withAnimation { insights.removeAll { $0.id == insight.id } }
        do { try await api.delete("/insights/\(insight.id)") } catch {}
    }

    // MARK: - Data Loading

    private func loadAll() async {
        loading = journey == nil
        reflection = nil
        reflectionTimedOut = false
        let (from, to) = selectedPeriod.dateRange

        do {
            journey = try await api.get("/goals/journey?from=\(from)&to=\(to)")
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Journey", "Failed to load journey: \(error)")
            }
        }
        loading = false

        // Load reflection and insights in parallel
        reflectionLoading = true
        async let reflectionTask: () = loadReflectionData(from: from, to: to)
        async let insightsTask: () = loadInsights()
        _ = await (reflectionTask, insightsTask)
    }

    private func loadReflectionData(from: String, to: String) async {
        do {
            let result: ReflectionResponse = try await api.get("/goals/journey/reflection?from=\(from)&to=\(to)")
            withAnimation(.easeIn(duration: 0.3)) { reflection = result.reflection }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Journey", "Failed to load reflection: \(error)")
            }
        }
        reflectionLoading = false
    }

    private func loadInsights() async {
        do {
            let items: [InsightItem] = try await api.get("/insights?page=1&pageSize=10")
            withAnimation(.easeIn(duration: 0.3)) { insights = items }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Journey", "Failed to load insights: \(error)")
            }
        }
    }
}

// MARK: - Practice progress ring

private struct PracticeRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let progress = total > 0 ? Double(done) / Double(total) : 0

        ZStack {
            Circle()
                .stroke(Color.sacredMuted.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [.sacredGoldShine, .sacredGold], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(done)")
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
        }
    }
}

// MARK: - Period

enum JourneyPeriod: CaseIterable {
    case yesterday, lastWeek, lastMonth, lastYear, all

    var label: String {
        switch self {
        case .yesterday: return "Yesterday"
        case .lastWeek: return "Last week"
        case .lastMonth: return "Last month"
        case .lastYear: return "Last year"
        case .all: return "All"
        }
    }

    var dateRange: (String, String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let cal = Calendar.current

        switch self {
        case .yesterday:
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            return (f.string(from: yesterday), f.string(from: yesterday))
        case .lastWeek:
            let from = cal.date(byAdding: .day, value: -7, to: today)!
            return (f.string(from: from), f.string(from: today))
        case .lastMonth:
            let from = cal.date(byAdding: .day, value: -30, to: today)!
            return (f.string(from: from), f.string(from: today))
        case .lastYear:
            let from = cal.date(byAdding: .day, value: -365, to: today)!
            return (f.string(from: from), f.string(from: today))
        case .all:
            let from = cal.date(byAdding: .year, value: -5, to: today)!
            return (f.string(from: from), f.string(from: today))
        }
    }
}

// MARK: - Models

struct JourneyData: Codable {
    let from: String
    let to: String
    let totalDays: Int
    let practices: [JourneyPractice]
    let completedCommitments: [JourneyCommitment]
    let summary: JourneySummary
}

struct JourneyPractice: Codable, Identifiable {
    let id: String
    let title: String
    let daysCompleted: Int
    let totalDays: Int
    let currentStreak: Int
    let longestStreak: Int
    let days: [JourneyDay]
}

struct JourneyDay: Codable {
    let date: String
    let completed: Bool
}

struct JourneySummary: Codable {
    let practicesCompleted: Int
    let practicesPossible: Int
    let completionRate: Int
    let commitmentsFinished: Int
}

struct JourneyCommitment: Codable, Identifiable {
    let id: String
    let title: String
    let completedAt: String?
}

struct ReflectionResponse: Codable {
    let reflection: String?
}

struct InsightItem: Codable, Identifiable {
    let id: String
    let content: String
    let sourceConversationId: String?
    let sourceJournalId: String?
    let createdAt: String
}
