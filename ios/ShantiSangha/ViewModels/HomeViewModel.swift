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

/// One starter chip under the Ask pill: `label` is the chip text, `prompt`
/// is the message auto-sent to the assistant when tapped.
struct StarterPrompt: Equatable, Identifiable {
    let label: String
    let prompt: String
    var id: String { label }
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

    // MARK: - Starter chips

    /// Two living invitations under the Ask pill. Situational chips win
    /// (something is overdue, something is due today, the evening hasn't been
    /// reflected on); a small day-rotated pool fills the remaining slots so
    /// the pair is never identical for weeks on end.
    var starterPrompts: [StarterPrompt] {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0

        var chips: [StarterPrompt] = []

        if overdueRemindersCount > 0 {
            chips.append(StarterPrompt(
                label: "What's been waiting on me?",
                prompt: "Some of my reminders have slipped past their dates. Walk me through what's been waiting and help me decide what to do with each."))
        }
        if dueTodayRemindersCount > 0 {
            chips.append(StarterPrompt(
                label: "What's on today?",
                prompt: "What's on my plate today?"))
        }
        if hour >= 17, presence?.reflectedToday == false {
            chips.append(StarterPrompt(
                label: "Look back on today",
                prompt: "Help me look back on today for a moment."))
        }

        var pool: [StarterPrompt] = [
            StarterPrompt(
                label: "What's due this week?",
                prompt: "What's due this week?"),
            StarterPrompt(
                label: "How have I been lately?",
                prompt: "How have I been lately?"),
            StarterPrompt(
                label: "What have I been circling?",
                prompt: "Looking at my recent reflections, what themes keep coming up?"),
            StarterPrompt(
                label: "Anything slipping through?",
                prompt: "Is anything slipping through the cracks — things I mentioned but haven't acted on?"),
        ]

        var poolIndex = dayOfYear % pool.count
        while chips.count < 2 {
            let candidate = pool[poolIndex % pool.count]
            poolIndex += 1
            if !chips.contains(candidate) { chips.append(candidate) }
        }

        return Array(chips.prefix(2))
    }

    private func completedWithinDays(_ dateStr: String?, _ days: Int) -> Bool {
        guard let dateStr, let date = Self.parseISODate(dateStr) else { return false }
        let daysAgo = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
        return daysAgo <= days
    }

    /// Lenient ISO-8601 parsing. The backend serializes DateTime with up to
    /// 7 fractional digits, which ISO8601DateFormatter's fractional mode
    /// rejects — so fall back to parsing with the fraction stripped.
    static func parseISODate(_ dateStr: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: dateStr) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: dateStr) { return date }
        if let dot = dateStr.firstIndex(of: ".") {
            return basic.date(from: String(dateStr[..<dot]) + "Z")
        }
        return nil
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
