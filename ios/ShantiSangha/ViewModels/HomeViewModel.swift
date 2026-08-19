import Foundation
import Combine
import SwiftUI

/// Response of GET /api/memory/presence — days with a journal, voice note, or
/// substantive companion message in the last `windowDays` local days.
struct MemoryPresence: Decodable, Equatable {
    let daysReflected: Int
    let windowDays: Int
    let reflectedToday: Bool
}

/// ViewModel for the Home screen — "What needs your attention today?"
/// Reminders are the only thing on this surface now; they're served by
/// `ReminderRepository` (online, no streaks).
@MainActor
class HomeViewModel: ObservableObject {
    @Published var loading = true
    @Published var activeSwipeId: String?

    /// Quiet continuity under the greeting — nil until loaded; the view hides
    /// the line entirely at 0 days (acknowledgment only, never guilt).
    @Published var presence: MemoryPresence?

    private let reminderRepo = ReminderRepository.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Reminders

    var reminders: [Reminder] { reminderRepo.reminders }

    /// Pending reminders — not completed, sorted by urgency (overdue first).
    var pendingReminders: [Reminder] {
        reminders.filter { $0.completedAt == nil }
            .sorted { $0.localDaysRemaining < $1.localDaysRemaining }
    }

    var completedReminders: [Reminder] {
        reminders.filter { $0.completedAt != nil }
    }

    var overdueRemindersCount: Int {
        pendingReminders.filter { $0.localDaysRemaining < 0 }.count
    }
    var dueTodayRemindersCount: Int {
        pendingReminders.filter { $0.localDaysRemaining == 0 }.count
    }
    var upcomingRemindersCount: Int {
        pendingReminders.filter { $0.localDaysRemaining > 0 }.count
    }

    /// Total reminders in scope for the Home ring (overdue + today + upcoming-this-week).
    var totalRemindersForToday: Int {
        pendingReminders.filter { $0.localDaysRemaining <= 7 }.count
    }
    var doneRemindersForToday: Int {
        // Reminders completed within the last 7 days
        completedReminders.filter { completedWithinDays($0.completedAt, 7) }.count
    }
    var remindersOverdue: Bool { overdueRemindersCount > 0 }

    var remindersSummaryDetail: String {
        var parts: [String] = []
        if overdueRemindersCount > 0 { parts.append("\(overdueRemindersCount) carried over") }
        if dueTodayRemindersCount > 0 { parts.append("\(dueTodayRemindersCount) due today") }
        if parts.isEmpty {
            if upcomingRemindersCount > 0 {
                return "\(upcomingRemindersCount) upcoming"
            }
            return "\(pendingReminders.count) active"
        }
        return parts.joined(separator: "\n")
    }

    private func completedWithinDays(_ dateStr: String?, _ days: Int) -> Bool {
        guard let dateStr = dateStr else { return false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) else { return false }
        let daysAgo = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
        return daysAgo <= days
    }

    init() {
        // Forward repo changes to trigger view updates
        reminderRepo.$reminders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        reminderRepo.$loading
            .receive(on: DispatchQueue.main)
            .assign(to: &$loading)
    }

    func load() async {
        await reminderRepo.refresh()
    }

    func loadPresence() async {
        do {
            let tzOffsetMinutes = TimeZone.current.secondsFromGMT() / 60
            let loaded: MemoryPresence = try await ApiService.shared
                .get("/memory/presence?tzOffsetMinutes=\(tzOffsetMinutes)")
            withAnimation(.easeIn(duration: 0.3)) {
                presence = loaded
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Home", "Failed to load presence: \(error)")
            }
        }
    }

    // MARK: - Reminder operations

    func createReminder(label: String,
                        date: String,
                        recurrence: ReminderRecurrence = .none,
                        remindersEnabled: Bool = true,
                        connectionId: UUID? = nil,
                        collaboratorUserIds: [UUID]? = nil) async {
        do {
            _ = try await reminderRepo.create(
                label: label,
                date: date,
                recurrence: recurrence,
                remindersEnabled: remindersEnabled,
                connectionId: connectionId,
                collaboratorUserIds: collaboratorUserIds)
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Home", "Failed to create reminder: \(error)")
            }
        }
    }

    func updateReminder(id: UUID,
                        label: String? = nil,
                        date: String? = nil,
                        recurrence: ReminderRecurrence? = nil,
                        remindersEnabled: Bool? = nil,
                        completed: Bool? = nil,
                        collaboratorUserIds: [UUID]? = nil) async {
        do {
            _ = try await reminderRepo.update(
                id: id, label: label, date: date,
                recurrence: recurrence, remindersEnabled: remindersEnabled,
                completed: completed,
                collaboratorUserIds: collaboratorUserIds)
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Home", "Failed to update reminder: \(error)")
            }
        }
    }

    func completeReminder(id: UUID) async {
        await updateReminder(id: id, completed: true)
    }

    func deleteReminder(id: UUID) async {
        do {
            try await reminderRepo.delete(id: id)
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Home", "Failed to delete reminder: \(error)")
            }
        }
    }
}
