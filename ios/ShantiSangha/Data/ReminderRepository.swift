import Foundation

/// Repository for reminders (the new module that unifies the legacy
/// one-time goals + connection "important dates"). Talks directly to
/// the backend — reminders aren't streak-tracked so they don't need
/// the offline-first SwiftData cache that practices get.
@MainActor
final class ReminderRepository: ObservableObject {
    static let shared = ReminderRepository()

    @Published var reminders: [Reminder] = []
    @Published var loading = false

    private let api = ApiService.shared

    // MARK: - Reads

    /// Fetches reminders, optionally filtered by connection / date.
    @discardableResult
    func list(connectionId: UUID? = nil, date: String? = nil) async throws -> [Reminder] {
        var query: [String] = []
        if let connectionId {
            query.append("connectionId=\(connectionId.uuidString.lowercased())")
        }
        if let date {
            query.append("date=\(date)")
        }
        let path = "/reminders" + (query.isEmpty ? "" : "?\(query.joined(separator: "&"))")
        let items: [Reminder] = try await api.get(path)
        // Keep the published list in sync only when an unfiltered fetch
        // happens; per-connection fetches shouldn't clobber the global cache.
        if connectionId == nil && date == nil {
            reminders = items
        }
        return items
    }

    /// Pull the full user-wide reminder list and publish it.
    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            reminders = try await api.get("/reminders")
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Reminders", "Refresh failed: \(error)")
            }
        }
    }

    func get(id: UUID) async throws -> Reminder {
        try await api.get("/reminders/\(id.uuidString.lowercased())")
    }

    // MARK: - Writes

    @discardableResult
    func create(label: String,
                date: String,
                recurrence: ReminderRecurrence = .none,
                remindersEnabled: Bool = true,
                connectionId: UUID? = nil) async throws -> Reminder {
        let body = CreateReminderRequest(
            label: label,
            date: date,
            recurrence: recurrence,
            remindersEnabled: remindersEnabled,
            connectionId: connectionId)
        let created: Reminder = try await api.post("/reminders", body: body)
        if connectionId == nil {
            reminders.insert(created, at: 0)
        }
        return created
    }

    @discardableResult
    func update(id: UUID,
                label: String? = nil,
                date: String? = nil,
                recurrence: ReminderRecurrence? = nil,
                remindersEnabled: Bool? = nil,
                completed: Bool? = nil) async throws -> Reminder {
        let body = UpdateReminderRequest(
            label: label,
            date: date,
            recurrence: recurrence,
            remindersEnabled: remindersEnabled,
            completed: completed)
        let updated: Reminder = try await api.patch(
            "/reminders/\(id.uuidString.lowercased())",
            body: body)
        if let idx = reminders.firstIndex(where: { $0.id == id }) {
            reminders[idx] = updated
        }
        return updated
    }

    @discardableResult
    func markComplete(id: UUID) async throws -> Reminder {
        try await update(id: id, completed: true)
    }

    func delete(id: UUID) async throws {
        try await api.delete("/reminders/\(id.uuidString.lowercased())")
        reminders.removeAll { $0.id == id }
    }
}
