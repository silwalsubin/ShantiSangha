import Foundation

/// Whether a `Reminder` repeats. `yearly` rolls forward each year
/// (birthday, anniversary). `none` pins to its absolute calendar slot.
enum ReminderRecurrence: String, Codable {
    case none = "none"
    case yearly = "yearly"
}

/// Mirror of backend `ReminderResponse`. Unified replacement for the
/// old OneTime goal + ConnectionDate. When `connectionId` is set the
/// reminder is scoped to a person in the user's circle; otherwise it's
/// a personal reminder.
struct Reminder: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let label: String
    /// ISO `yyyy-MM-dd` from backend's `DateOnly`.
    let date: String
    let recurrence: ReminderRecurrence
    let remindersEnabled: Bool
    let connectionId: UUID?
    let completedAt: String?
    let createdAt: String
    let daysRemaining: Int

    /// Device-local interpretation of the backend's DateOnly string.
    /// The API's `daysRemaining` can drift around UTC/local midnight;
    /// UI, widgets, and notifications should read this value instead.
    var localDaysRemaining: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let parts = Self.parseDateParts(date) else { return daysRemaining }
        let today = calendar.startOfDay(for: Date())

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = recurrence == .yearly ? calendar.component(.year, from: today) : parts.year
        components.month = parts.month
        components.day = parts.day

        guard var due = calendar.date(from: components) else { return daysRemaining }
        due = calendar.startOfDay(for: due)

        if recurrence == .yearly && due < today,
           let nextYear = calendar.date(byAdding: .year, value: 1, to: due) {
            due = nextYear
        }

        return calendar.dateComponents([.day], from: today, to: due).day ?? daysRemaining
    }

    private static func parseDateParts(_ value: String) -> (year: Int, month: Int, day: Int)? {
        let parts = value.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return (year, month, day)
    }
}

struct CreateReminderRequest: Encodable {
    let label: String
    let date: String   // yyyy-MM-dd
    var recurrence: ReminderRecurrence? = nil
    var remindersEnabled: Bool? = nil
    var connectionId: UUID? = nil
}

struct UpdateReminderRequest: Encodable {
    var label: String? = nil
    var date: String? = nil
    var recurrence: ReminderRecurrence? = nil
    var remindersEnabled: Bool? = nil
    var completed: Bool? = nil
}
