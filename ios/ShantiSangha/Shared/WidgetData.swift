import Foundation

/// Compact snapshot of one reminder for the widget. Avatars / connection
/// details aren't included — widgets can't load remote images cleanly
/// without async work, so the widget stays text-only.
struct WidgetReminderSummary: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    /// 3-letter uppercase month, e.g. "MAY".
    let monthAbbreviation: String
    let day: Int
    /// Server-computed days until the next occurrence (negative = overdue).
    let daysRemaining: Int
    /// Nickname / display name of the connection this reminder belongs
    /// to, or nil for personal reminders. Rendered as "Didi · Birthday".
    var connectionLabel: String? = nil
    /// "none" or "yearly" — needed so the widget computes days against the
    /// next occurrence for yearly anchors (birthdays) instead of the
    /// original anchor year. Optional for backward compat with snapshots
    /// written before this field existed.
    var recurrence: String? = nil
}

/// Shared data between the main app and widget extension.
/// Both sides use the same App Group UserDefaults.
enum WidgetData {
    static let appGroupId = "group.com.shantisangha.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Reminders

    /// The top N upcoming reminders the widget should render, ordered by
    /// urgency (overdue → today → upcoming). The main app caps the list
    /// at a handful of items — widgets re-fetch from this on every
    /// timeline reload, so there's no point storing more than the widget
    /// can show.
    static var upcomingReminders: [WidgetReminderSummary] {
        get {
            guard let data = defaults?.data(forKey: "widget.upcomingReminders") else { return [] }
            return (try? JSONDecoder().decode([WidgetReminderSummary].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults?.set(data, forKey: "widget.upcomingReminders")
        }
    }

    // MARK: - User

    static var userName: String? {
        get { defaults?.string(forKey: "widget.userName") }
        set { defaults?.set(newValue, forKey: "widget.userName") }
    }

    // MARK: - Last updated

    static var lastUpdated: Date? {
        get { defaults?.object(forKey: "widget.lastUpdated") as? Date }
        set { defaults?.set(newValue, forKey: "widget.lastUpdated") }
    }

    /// Call from the main app whenever data changes to keep widget fresh
    static func update(
        upcomingReminders: [WidgetReminderSummary],
        userName: String?
    ) {
        self.upcomingReminders = upcomingReminders
        self.userName = userName
        self.lastUpdated = Date()
    }

    // MARK: - Helpers

    /// Maps a 1-based month number to its 3-letter uppercase abbreviation.
    /// Shared between main app + widget so both render the same labels.
    static func monthAbbreviation(_ monthNumber: Int) -> String {
        let names = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                     "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        guard (1...12).contains(monthNumber) else { return "" }
        return names[monthNumber - 1]
    }

    /// Builds a `WidgetReminderSummary` from a "yyyy-MM-dd" date string.
    /// Returns nil if the string is malformed. `recurrence` should be
    /// "none" or "yearly" — yearly anchors get their month/day projected
    /// onto the current year (or next year if already past) so the widget
    /// doesn't report a birthday set in 1987 as "14245 days ago".
    static func makeSummary(
        id: String,
        label: String,
        date: String,
        daysRemaining: Int,
        recurrence: String? = nil,
        connectionLabel: String? = nil
    ) -> WidgetReminderSummary? {
        let parts = date.split(separator: "-")
        guard parts.count >= 3,
              let monthNum = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return WidgetReminderSummary(
            id: id,
            label: label,
            monthAbbreviation: monthAbbreviation(monthNum),
            day: day,
            daysRemaining: localDaysRemaining(from: date, recurrence: recurrence) ?? daysRemaining,
            connectionLabel: connectionLabel,
            recurrence: recurrence
        )
    }

    private static func localDaysRemaining(from date: String, recurrence: String?) -> Int? {
        let parts = date.split(separator: "-")
        guard parts.count >= 3,
              let anchorYear = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())

        let isYearly = recurrence?.lowercased() == "yearly"
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = isYearly ? calendar.component(.year, from: today) : anchorYear
        components.month = month
        components.day = day

        guard var due = calendar.date(from: components) else { return nil }
        due = calendar.startOfDay(for: due)

        if isYearly && due < today,
           let nextYear = calendar.date(byAdding: .year, value: 1, to: due) {
            due = nextYear
        }

        return calendar.dateComponents([.day], from: today, to: due).day
    }
}
