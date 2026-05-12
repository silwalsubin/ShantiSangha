import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ShantiSanghaEntry: TimelineEntry {
    let date: Date
    let reflection: String?
    let remindersOverdue: Int
    let remindersDueToday: Int
    let userName: String?
}

// MARK: - Timeline Provider

struct ShantiSanghaProvider: TimelineProvider {

    func placeholder(in context: Context) -> ShantiSanghaEntry {
        ShantiSanghaEntry(
            date: Date(),
            reflection: "Your practice has a rhythm now. The days you show up are the ones you shape.",
            remindersOverdue: 0, remindersDueToday: 1,
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
            reflection: WidgetData.reflection,
            remindersOverdue: WidgetData.remindersOverdue,
            remindersDueToday: WidgetData.remindersDueToday,
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

// MARK: - Small Widget (Reflection only)

struct ReflectionWidgetView: View {
    let entry: ShantiSanghaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundColor(sacredGold)

            Spacer()

            if let reflection = entry.reflection, !reflection.isEmpty {
                Text(reflection)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(sacredText)
                    .lineLimit(6)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
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

// MARK: - Medium Widget (Reflection + Reminders)

struct DashboardWidgetView: View {
    let entry: ShantiSanghaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reflection — primary content. Hard-cap to 5 lines and let
            // SwiftUI truncate with an ellipsis. Never use
            // `fixedSize(vertical: true)` here — it would let the Text grow
            // past the widget's bounds and mangle the layout.
            if let reflection = entry.reflection, !reflection.isEmpty {
                Text(reflection)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(sacredText)
                    .lineLimit(5)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text("Open the app — today's reflection is being written.")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundColor(sacredTextSecondary)
            }

            Spacer()

            // Reminders summary at bottom
            if entry.remindersOverdue > 0 || entry.remindersDueToday > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10))
                    if entry.remindersOverdue > 0 {
                        Text("\(entry.remindersOverdue) carried over")
                    }
                    if entry.remindersDueToday > 0 {
                        if entry.remindersOverdue > 0 { Text("·") }
                        Text("\(entry.remindersDueToday) today")
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

struct ShantiSanghaReflectionWidget: Widget {
    let kind: String = "ShantiSanghaReflection"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShantiSanghaProvider()) { entry in
            if #available(iOS 17.0, *) {
                ReflectionWidgetView(entry: entry)
                    .containerBackground(for: .widget) {
                        SacredWidgetBackground()
                    }
            } else {
                ReflectionWidgetView(entry: entry)
                    .background(SacredWidgetBackground())
            }
        }
        .configurationDisplayName("Daily Reflection")
        .description("A personal observation the app wrote for you today.")
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
                        SacredWidgetBackground()
                    }
            } else {
                DashboardWidgetView(entry: entry)
                    .background(SacredWidgetBackground())
            }
        }
        .configurationDisplayName("Today's Reflection")
        .description("Your daily reflection and reminders that need you.")
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
