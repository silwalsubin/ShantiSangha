import SwiftUI

/// Journey — "How am I actually doing?"
struct JourneyView: View {
    @State private var journey: JourneyData?
    @State private var reflection: String?
    @State private var loading = true
    @State private var reflectionLoading = false
    @State private var selectedPeriod: JourneyPeriod = .week
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
                .padding(.bottom, 24)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let journey = journey {
                    // Celebration header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(journey.summary.practicesCompleted)")
                            .font(.system(size: 52, weight: .bold, design: .serif))
                            .foregroundColor(.sacredGold)
                        + Text(" practices")
                            .font(.sacredTitle)
                            .foregroundColor(.sacredText)

                        if journey.summary.completionRate > 0 {
                            Text("\(journey.summary.completionRate)% consistency")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }

                        if journey.summary.commitmentsFinished > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.sacredGreen)
                                Text("\(journey.summary.commitmentsFinished) commitment\(journey.summary.commitmentsFinished == 1 ? "" : "s") fulfilled")
                                    .font(.sacredSmallMedium)
                                    .foregroundColor(.sacredGreen)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, 20)

                    // AI Reflection
                    if reflectionLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Reflecting...")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)
                    } else if let reflection = reflection {
                        Text(reflection)
                            .font(.sacredBody)
                            .italic()
                            .foregroundColor(.sacredText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredGold.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.1)))
                            .padding(.bottom, 28)
                    }

                    // Rhythm grid
                    if !journey.practices.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(journey.practices) { practice in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(practice.title)
                                            .font(.sacredSmallMedium)
                                            .foregroundColor(.sacredText)
                                        Spacer()
                                        Text("\(practice.daysCompleted)/\(practice.totalDays)")
                                            .font(.sacredMicro)
                                            .foregroundColor(.sacredMuted)
                                    }

                                    RhythmRow(days: practice.days)
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

                        VStack(alignment: .leading, spacing: 12) {
                            Text("FULFILLED")
                                .font(.sacredSectionLabel)
                                .tracking(3)
                                .foregroundColor(.sacredLabel)
                                .padding(.bottom, 4)

                            ForEach(journey.completedCommitments) { c in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.sacredText)
                                        .foregroundColor(.sacredGreen)
                                    Text(c.title)
                                        .font(.sacredTextMedium)
                                        .foregroundColor(.sacredText)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.sacredGreen.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sacredGreen.opacity(0.12)))
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

    private func loadAll() async {
        loading = journey == nil
        reflection = nil
        let (from, to) = selectedPeriod.dateRange

        do {
            journey = try await api.get("/goals/journey?from=\(from)&to=\(to)")
        } catch {
            print("Failed to load journey: \(error)")
        }
        loading = false

        // Load reflection in background
        reflectionLoading = true
        do {
            let result: ReflectionResponse = try await api.get("/goals/journey/reflection?from=\(from)&to=\(to)")
            withAnimation(.easeIn(duration: 0.3)) { reflection = result.reflection }
        } catch {
            print("Failed to load reflection: \(error)")
        }
        reflectionLoading = false
    }
}

// MARK: - Rhythm row — rounded squares, height varies by completion

private struct RhythmRow: View {
    let days: [JourneyDay]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 4)
                    .fill(day.completed ? Color.sacredGold : Color.sacredMuted.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: day.completed ? 24 : 6)
            }
        }
        .frame(height: 24, alignment: .bottom)
    }
}

// MARK: - Period

enum JourneyPeriod: CaseIterable {
    case week, twoWeeks, month, threeMonths

    var label: String {
        switch self {
        case .week: return "7D"
        case .twoWeeks: return "14D"
        case .month: return "30D"
        case .threeMonths: return "90D"
        }
    }

    var dateRange: (String, String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let daysBack: Int
        switch self {
        case .week: daysBack = 6
        case .twoWeeks: daysBack = 13
        case .month: daysBack = 29
        case .threeMonths: daysBack = 89
        }
        let from = Calendar.current.date(byAdding: .day, value: -daysBack, to: today)!
        return (f.string(from: from), f.string(from: today))
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
