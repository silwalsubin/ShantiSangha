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
