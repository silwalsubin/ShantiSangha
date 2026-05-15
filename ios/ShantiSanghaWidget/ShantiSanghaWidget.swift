import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ShantiSanghaEntry: TimelineEntry {
    let date: Date
    let upcomingReminders: [WidgetReminderSummary]
    let userName: String?
}

// MARK: - Timeline Provider

struct ShantiSanghaProvider: TimelineProvider {

    func placeholder(in context: Context) -> ShantiSanghaEntry {
        ShantiSanghaEntry(
            date: Date(),
            upcomingReminders: [
                WidgetReminderSummary(
                    id: "placeholder-1",
                    label: "Birthday",
                    monthAbbreviation: "MAY",
                    day: 16,
                    daysRemaining: 4,
                    connectionLabel: "Didi"),
                WidgetReminderSummary(
                    id: "placeholder-2",
                    label: "Call mom",
                    monthAbbreviation: "MAY",
                    day: 18,
                    daysRemaining: 6,
                    connectionLabel: nil),
                WidgetReminderSummary(
                    id: "placeholder-3",
                    label: "Anniversary",
                    monthAbbreviation: "JUN",
                    day: 5,
                    daysRemaining: 24,
                    connectionLabel: "Sarah")
            ],
            userName: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ShantiSanghaEntry) -> Void) {
        completion(localEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShantiSanghaEntry>) -> Void) {
        // Read from shared WidgetData (written by main app and SilentPushHandler).
        // The main app updates WidgetData on open, and silent pushes refresh it
        // in the background — no need for the widget to make its own API calls.
        let entry = localEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func localEntry() -> ShantiSanghaEntry {
        ShantiSanghaEntry(
            date: Date(),
            upcomingReminders: WidgetData.upcomingReminders,
            userName: WidgetData.userName
        )
    }

}

// MARK: - Sacred widget background
//
// Mirrors `SacredBackground` + `LuxCard` chrome from the main app, scaled for
// the widget canvas. The widget itself acts as the lux card on the home
// screen — parchment fill, soft gold corner radials, and a diagonal
// gold-gradient highlight that gives the surface a subtle metallic feel.
// Duplicated here (rather than imported) because widget extensions can't
// link main-app code.
private struct SacredWidgetBackground: View {
    var body: some View {
        ZStack {
            sacredBg

            // Top-down golden warmth
            LinearGradient(
                colors: [sacredGoldShine.opacity(0.16), sacredBg.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )

            // Top-left soft gold halo
            RadialGradient(
                colors: [sacredGold.opacity(0.11), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 140
            )

            // Bottom-right deeper gold
            RadialGradient(
                colors: [sacredGoldDark.opacity(0.06), .clear],
                center: .bottomTrailing,
                startRadius: 4,
                endRadius: 150
            )

            // LuxCard diagonal highlight — gives a metallic shimmer
            LinearGradient(
                colors: [
                    sacredGoldShine.opacity(0.1),
                    .clear,
                    sacredGoldDark.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Date stamp tile

private struct MiniDateStamp: View {
    let month: String
    let day: Int
    let daysRemaining: Int

    var body: some View {
        VStack(spacing: -1) {
            Text(month)
                .font(.system(size: 7, weight: .bold, design: .serif))
                .tracking(0.5)
                .foregroundColor(monthColor)
            Text("\(day)")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundColor(dayColor)
        }
        .frame(width: 30, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(strokeColor, lineWidth: 1)
                )
        )
    }

    private var isPast: Bool { daysRemaining < 0 }
    private var isToday: Bool { daysRemaining == 0 }

    private var monthColor: Color {
        if isPast { return sacredMuted.opacity(0.62) }
        if isToday { return sacredTextSecondary }
        return sacredMuted
    }

    private var dayColor: Color {
        if isPast { return sacredMuted }
        if isToday { return sacredGold }
        return sacredText
    }

    private var backgroundColor: Color {
        if isPast { return sacredBgCard.opacity(0.56) }
        if isToday { return sacredGold.opacity(0.12) }
        return sacredBgCard
    }

    private var strokeColor: Color {
        if isPast { return sacredRed.opacity(0.16) }
        if isToday { return sacredGold.opacity(0.22) }
        return .clear
    }
}

private func relativeDayLabel(_ days: Int) -> String? {
    if days < -1 { return "\(abs(days)) days ago" }
    if days == -1 { return "Yesterday" }
    if days == 0 { return "Today" }
    if days == 1 { return "Tomorrow" }
    if days < 14 { return "in \(days) days" }
    return nil  // far-future reminders rely on the date stamp itself
}

private func relativeDayColor(_ days: Int) -> Color {
    if days < 0 { return sacredRed }
    if days == 0 { return sacredGold }
    return sacredMuted
}

/// "{Connection} · {label}" when the reminder belongs to a connection;
/// just the label otherwise. The connection prefix is rendered slightly
/// bolder so the eye lands on the person first.
private func reminderLabelText(_ r: WidgetReminderSummary) -> Text {
    if let conn = r.connectionLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
       !conn.isEmpty {
        var attr = AttributedString()

        var nameAttrs = AttributeContainer()
        nameAttrs.inlinePresentationIntent = .stronglyEmphasized
        attr.append(AttributedString(conn, attributes: nameAttrs))

        var sepAttrs = AttributeContainer()
        sepAttrs.foregroundColor = sacredMuted
        attr.append(AttributedString(" · ", attributes: sepAttrs))

        attr.append(AttributedString(r.label))
        return Text(attr)
    }
    return Text(r.label)
}

// MARK: - Small Widget (Next reminder)

struct NextReminderWidgetView: View {
    let entry: ShantiSanghaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let top = entry.upcomingReminders.first {
                Spacer(minLength: 0)

                HStack(alignment: .top, spacing: 8) {
                    MiniDateStamp(month: top.monthAbbreviation,
                                  day: top.day,
                                  daysRemaining: top.daysRemaining)
                    VStack(alignment: .leading, spacing: 2) {
                        reminderLabelText(top)
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(sacredText)
                            .lineLimit(2)
                        if let label = relativeDayLabel(top.daysRemaining) {
                            Text(label)
                                .font(.system(size: 10, design: .serif))
                                .foregroundColor(relativeDayColor(top.daysRemaining))
                        }
                    }
                }

                Spacer(minLength: 0)

                if entry.upcomingReminders.count > 1 {
                    Text("+ \(entry.upcomingReminders.count - 1) more")
                        .font(.system(size: 10, design: .serif))
                        .foregroundColor(sacredMuted)
                }
            } else {
                Spacer(minLength: 0)
                Text("Nothing on the horizon.")
                    .font(.system(size: 12, design: .serif))
                    .italic()
                    .foregroundColor(sacredTextSecondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium Widget (Upcoming reminders list)

struct UpcomingWidgetView: View {
    let entry: ShantiSanghaEntry

    private let visibleCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.upcomingReminders.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing on the horizon.")
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundColor(sacredTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.upcomingReminders.prefix(visibleCount))) { r in
                    HStack(spacing: 10) {
                        MiniDateStamp(month: r.monthAbbreviation,
                                      day: r.day,
                                      daysRemaining: r.daysRemaining)
                        VStack(alignment: .leading, spacing: 1) {
                            reminderLabelText(r)
                                .font(.system(size: 12, design: .serif))
                                .foregroundColor(sacredText)
                                .lineLimit(1)
                            if let label = relativeDayLabel(r.daysRemaining) {
                                Text(label)
                                    .font(.system(size: 9, design: .serif))
                                    .foregroundColor(relativeDayColor(r.daysRemaining))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                if entry.upcomingReminders.count > visibleCount {
                    HStack {
                        Spacer()
                        Text("+ \(entry.upcomingReminders.count - visibleCount) more")
                            .font(.system(size: 10, design: .serif))
                            .foregroundColor(sacredMuted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget Configuration

struct ShantiSanghaReflectionWidget: Widget {
    /// Kind string kept stable as `ShantiSanghaReflection` even though the
    /// surface is now reminders — changing it would invalidate widgets
    /// users have already pinned to their home screen.
    let kind: String = "ShantiSanghaReflection"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShantiSanghaProvider()) { entry in
            // iOS 17+ applies ~16pt content margins automatically when
            // `.containerBackground` is used, so the view itself adds no
            // inner padding. Pre-iOS-17 has no system margins, so we
            // restore the explicit padding on the fallback path.
            if #available(iOS 17.0, *) {
                NextReminderWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        SacredWidgetBackground()
                    }
            } else {
                NextReminderWidgetView(entry: entry)
                    .padding(14)
                    .background(SacredWidgetBackground())
            }
        }
        .configurationDisplayName("Next Reminder")
        .description("The next reminder needing your attention.")
        .supportedFamilies([.systemSmall])
    }
}

struct ShantiSanghaDashboardWidget: Widget {
    let kind: String = "ShantiSanghaDashboard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShantiSanghaProvider()) { entry in
            if #available(iOS 17.0, *) {
                UpcomingWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        SacredWidgetBackground()
                    }
            } else {
                UpcomingWidgetView(entry: entry)
                    .padding(14)
                    .background(SacredWidgetBackground())
            }
        }
        .configurationDisplayName("Upcoming Reminders")
        .description("The next few reminders, dated.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct ShantiSanghaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShantiSanghaReflectionWidget()
        ShantiSanghaDashboardWidget()
    }
}

// MARK: - Sacred tokens (adaptive for light/dark mode)
//
// Widget extensions can't link to the main app target's `DesignTokens.swift`,
// so the same hex values are duplicated here. Keep them in sync with
// `ios/ShantiSangha/Models/DesignTokens.swift` if the palette ever shifts.

private let sacredBg = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(hex: "#1a1410") : UIColor(hex: "#faf5ed")
})

private let sacredBgCard = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(hex: "#2a1f15") : UIColor(hex: "#f0e6d6")
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
private let sacredGoldDark = Color(hex: "#8b5a1b")
private let sacredGoldShine = Color(hex: "#e8c47a")
private let sacredRed = Color(hex: "#b8503c")

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
