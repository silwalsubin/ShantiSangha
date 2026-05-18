import Foundation

/// Whether a `Reminder` repeats. `yearly` rolls forward each year
/// (birthday, anniversary). `none` pins to its absolute calendar slot.
enum ReminderRecurrence: String, Codable {
    case none = "none"
    case yearly = "yearly"
}

/// One person the reminder's owner has shared this reminder with. The
/// owner is NOT in this list — they're identified separately on the
/// `Reminder` itself.
struct ReminderCollaboratorSummary: Codable, Equatable, Hashable, Identifiable {
    let userId: UUID
    let displayName: String
    let avatarUrl: String?

    var id: UUID { userId }
}

/// Mirror of backend `ReminderResponse`. Unified replacement for the
/// old OneTime goal + ConnectionDate. When `connectionId` is set the
/// reminder is scoped to a person in the user's circle (owner-private
/// metadata). Collaboration is a separate concern — see `collaborators`
/// and `isSharedWithMe`.
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
    /// Friends the owner has shared this reminder with. Empty when
    /// the reminder is private. Encoded as `[]` on the wire even when
    /// empty; we decode missing payloads (older caches) as empty too.
    let collaborators: [ReminderCollaboratorSummary]
    /// True when the viewing user is a collaborator on this reminder
    /// rather than its owner. iOS uses this to swap the "Shared with"
    /// editor section for a "Shared by …" badge.
    let isSharedWithMe: Bool
    /// Display name of the reminder's owner — only present when
    /// `isSharedWithMe` is true. Used for the "Shared by …" line.
    let ownerDisplayName: String?

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

    /// True when at least one friend has been added as a collaborator.
    /// Use this from the UI to decide whether to render the avatar
    /// stack / shared chip, regardless of whether the viewer is the
    /// owner or a recipient.
    var isShared: Bool { !collaborators.isEmpty || isSharedWithMe }

    private static func parseDateParts(_ value: String) -> (year: Int, month: Int, day: Int)? {
        let parts = value.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return (year, month, day)
    }

    enum CodingKeys: String, CodingKey {
        case id, label, date, recurrence, remindersEnabled, connectionId
        case completedAt, createdAt, daysRemaining, collaborators
        case isSharedWithMe, ownerDisplayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        date = try c.decode(String.self, forKey: .date)
        recurrence = try c.decode(ReminderRecurrence.self, forKey: .recurrence)
        remindersEnabled = try c.decode(Bool.self, forKey: .remindersEnabled)
        connectionId = try c.decodeIfPresent(UUID.self, forKey: .connectionId)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        daysRemaining = try c.decode(Int.self, forKey: .daysRemaining)
        collaborators = try c.decodeIfPresent([ReminderCollaboratorSummary].self, forKey: .collaborators) ?? []
        isSharedWithMe = try c.decodeIfPresent(Bool.self, forKey: .isSharedWithMe) ?? false
        ownerDisplayName = try c.decodeIfPresent(String.self, forKey: .ownerDisplayName)
    }
}

struct CreateReminderRequest: Encodable {
    let label: String
    let date: String   // yyyy-MM-dd
    var recurrence: ReminderRecurrence? = nil
    var remindersEnabled: Bool? = nil
    var connectionId: UUID? = nil
    /// Friend user IDs to share this reminder with on creation. Each ID
    /// must be an accepted friend of the caller or the server rejects
    /// the whole request with 400.
    var collaboratorUserIds: [UUID]? = nil
}

struct UpdateReminderRequest: Encodable {
    var label: String? = nil
    var date: String? = nil
    var recurrence: ReminderRecurrence? = nil
    var remindersEnabled: Bool? = nil
    var completed: Bool? = nil
    /// Replaces the full collaborator set when non-nil. Pass nil to
    /// leave it untouched; pass an empty array to clear all sharing.
    /// Owner-only — non-owner collaborators sending this get 403.
    var collaboratorUserIds: [UUID]? = nil
}
