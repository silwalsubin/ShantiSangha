import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ShantiSanghaEntry: TimelineEntry {
    let date: Date
    let mantra: String?
    let practicesDone: Int
    let practicesTotal: Int
    let goalsOverdue: Int
    let goalsDueToday: Int
    let userName: String?
}

// MARK: - Timeline Provider

struct ShantiSanghaProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShantiSanghaEntry {
        ShantiSanghaEntry(
            date: Date(),
            mantra: "The breath you take right now is the only one that matters.",
            practicesDone: 2, practicesTotal: 4,
            goalsOverdue: 0, goalsDueToday: 1,
            userName: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ShantiSanghaEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShantiSanghaEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> ShantiSanghaEntry {
        ShantiSanghaEntry(
            date: Date(),
            mantra: WidgetData.mantra,
            practicesDone: WidgetData.practicesDone,
            practicesTotal: WidgetData.practicesTotal,
            goalsOverdue: WidgetData.goalsOverdue,
            goalsDueToday: WidgetData.goalsDueToday,
            userName: WidgetData.userName
        )
    }
}

// MARK: - Small Widget (Mantra only)

struct MantraWidgetView: View {
    let entry: ShantiSanghaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundColor(sacredGold)

            Spacer()

            if let mantra = entry.mantra, !mantra.isEmpty {
                Text(mantra)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(sacredText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Open the app to begin your practice.")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundColor(sacredTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium Widget (Progress + Mantra)

struct DashboardWidgetView: View {
    let entry: ShantiSanghaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Progress circle + label
                VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(sacredMuted.opacity(0.12), lineWidth: 5)
                    if entry.practicesTotal > 0 {
                        Circle()
                            .trim(from: 0, to: Double(entry.practicesDone) / Double(entry.practicesTotal))
                            .stroke(
                                sacredGold,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 0) {
                        Text("\(entry.practicesDone)")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundColor(sacredGold)
                        Text("of \(entry.practicesTotal)")
                            .font(.system(size: 8, design: .serif))
                            .foregroundColor(sacredMuted)
                    }
                }
                .frame(width: 52, height: 52)

                Text("Practices")
                    .font(.system(size: 9, weight: .semibold, design: .serif))
                    .foregroundColor(sacredTextSecondary)
                }

                // Mantra — takes remaining space
                if let mantra = entry.mantra, !mantra.isEmpty {
                    Text(mantra)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(sacredText)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            // Goals summary at bottom
            if entry.goalsOverdue > 0 || entry.goalsDueToday > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10))
                    if entry.goalsOverdue > 0 {
                        Text("\(entry.goalsOverdue) carried over")
                    }
                    if entry.goalsDueToday > 0 {
                        if entry.goalsOverdue > 0 { Text("·") }
                        Text("\(entry.goalsDueToday) today")
                    }
                }
                .font(.system(size: 10, design: .serif))
                .foregroundColor(sacredMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widget Configuration

struct ShantiSanghaMantraWidget: Widget {
    let kind: String = "ShantiSanghaMantra"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShantiSanghaProvider()) { entry in
            if #available(iOS 17.0, *) {
                MantraWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        sacredBg
                    }
            } else {
                MantraWidgetView(entry: entry)
                    .background(sacredBg)
            }
        }
        .configurationDisplayName("Daily Mantra")
        .description("Your personal mantra for the day.")
        .supportedFamilies([.systemSmall])
    }
}

struct ShantiSanghaDashboardWidget: Widget {
    let kind: String = "ShantiSanghaDashboard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShantiSanghaProvider()) { entry in
            if #available(iOS 17.0, *) {
                DashboardWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        sacredBg
                    }
            } else {
                DashboardWidgetView(entry: entry)
                    .background(sacredBg)
            }
        }
        .configurationDisplayName("Today's Practice")
        .description("Your daily practice progress and mantra.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct ShantiSanghaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShantiSanghaMantraWidget()
        ShantiSanghaDashboardWidget()
    }
}

// MARK: - Color helpers (adaptive for light/dark mode)

private let sacredBg = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(hex: "#1a1410") : UIColor(hex: "#faf5ed")
})

private let sacredText = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(hex: "#f5ebe0") : UIColor(hex: "#2b1e10")
})

private let sacredTextSecondary = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(hex: "#c4a882") : UIColor(hex: "#6b5740")
})

private let sacredMuted = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(hex: "#8a7a64") : UIColor(hex: "#9a8568")
})

private let sacredGold = Color(hex: "#c4873b")

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}
