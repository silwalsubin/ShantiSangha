import Foundation
import Combine

/// ViewModel for the Home screen — "What needs your attention today?"
/// Practices delegate to `PracticeRepository` for offline-first data;
/// reminders go through `ReminderRepository` (online, no streaks).
@MainActor
class HomeViewModel: ObservableObject {
    @Published var loading = true
    @Published var activeSwipeId: String?

    private let practiceRepo = PracticeRepository.shared
    private let reminderRepo = ReminderRepository.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Practices

    var practices: [Practice] { practiceRepo.practices }
    var hasPractices: Bool { !practices.isEmpty }

    /// Pending recurring practices (not checked in today)
    var pendingPractices: [Practice] {
        practices.filter { !$0.checkedIn }
    }

    /// All practices — pending first, then completed
    var allPractices: [Practice] {
        practices.sorted { !$0.checkedIn && $1.checkedIn }
    }

    var totalPractices: Int { practices.count }
    var donePractices: Int { practices.filter { $0.checkedIn }.count }
    var allPracticesDone: Bool { totalPractices > 0 && donePractices == totalPractices }

    var completedPractices: [Practice] {
        practices.filter { $0.checkedIn && $0.completedToday == true }
    }
    var skippedPractices: [Practice] {
        practices.filter { $0.checkedIn && $0.completedToday == false }
    }

    // MARK: - Reminders

    var reminders: [Reminder] { reminderRepo.reminders }

    /// Pending reminders — not completed, sorted by urgency (overdue first).
    var pendingReminders: [Reminder] {
        reminders.filter { $0.completedAt == nil }
            .sorted { $0.daysRemaining < $1.daysRemaining }
    }

    var completedReminders: [Reminder] {
        reminders.filter { $0.completedAt != nil }
    }

    var overdueRemindersCount: Int {
        pendingReminders.filter { $0.daysRemaining < 0 }.count
    }
    var dueTodayRemindersCount: Int {
        pendingReminders.filter { $0.daysRemaining == 0 }.count
    }
    var upcomingRemindersCount: Int {
        pendingReminders.filter { $0.daysRemaining > 0 }.count
    }

    /// Total reminders in scope for the Home ring (overdue + today + upcoming-this-week).
    var totalRemindersForToday: Int {
        pendingReminders.filter { $0.daysRemaining <= 7 }.count
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
        practiceRepo.$practices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        reminderRepo.$reminders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        practiceRepo.$loading
            .receive(on: DispatchQueue.main)
            .assign(to: &$loading)
    }

    func load() async {
        async let p: () = practiceRepo.refreshFromServer()
        async let r: () = reminderRepo.refresh()
        _ = await (p, r)
    }

    // MARK: - Practice operations

    func checkIn(id: String, completed: Bool) async {
        await practiceRepo.checkIn(id: id, completed: completed)
    }

    func undoCheckIn(id: String) async {
        await practiceRepo.undoCheckIn(id: id)
    }

    func deletePractice(id: String) async {
        await practiceRepo.deletePractice(id: id)
    }

    func createPractice(title: String, deeperWhy: String? = nil) async {
        await practiceRepo.createPractice(title: title, deeperWhy: deeperWhy)
    }

    // MARK: - Reminder operations

    func createReminder(label: String,
                        date: String,
                        recurrence: ReminderRecurrence = .none,
                        remindersEnabled: Bool = true,
                        connectionId: UUID? = nil) async {
        do {
            _ = try await reminderRepo.create(
                label: label,
                date: date,
                recurrence: recurrence,
                remindersEnabled: remindersEnabled,
                connectionId: connectionId)
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
                        completed: Bool? = nil) async {
        do {
            _ = try await reminderRepo.update(
                id: id, label: label, date: date,
                recurrence: recurrence, remindersEnabled: remindersEnabled,
                completed: completed)
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
