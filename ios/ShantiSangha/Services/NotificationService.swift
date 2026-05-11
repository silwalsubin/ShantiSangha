import Foundation
import UserNotifications

/// Schedules local notifications for streak protection and commitment reminders.
/// All notifications are local — no server push infrastructure needed.
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "notificationsEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "notificationsEnabled")
            Task { await syncReminderToServer() }
        }
    }

    @Published var reminderHour: Int = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 8 {
        didSet {
            UserDefaults.standard.set(reminderHour, forKey: "reminderHour")
            Task { await syncReminderToServer() }
        }
    }

    @Published var reminderMinute: Int = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(reminderMinute, forKey: "reminderMinute") }
    }

    /// PATCH /me with reminderHour so the backend morning-push job knows when
    /// to deliver today's reflection. When reminders are disabled, clears the
    /// stored hour so the job skips this user.
    private func syncReminderToServer() async {
        let body: [String: Any]
        if isEnabled {
            body = ["reminderHour": reminderHour]
        } else {
            body = ["clearReminderHour": true]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        struct Empty: Decodable {}
        let _: Empty? = try? await ApiService.shared.patchRaw("/me", body: data)
        AppLogger.shared.info("Notifications", "Reminder synced: enabled=\(isEnabled) hour=\(reminderHour)")
    }

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted { isEnabled = true }
            return granted
        } catch {
            return false
        }
    }

    func checkPermission() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule all notifications based on current state

    func reschedule(practices: [Practice], reminders: [Reminder]) {
        guard isEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        center.removeAllPendingNotificationRequests()

        let calendar = Calendar.current
        let now = Date()

        for practice in practices {
            scheduleStreakProtection(practice: practice, calendar: calendar, now: now)
        }
        for reminder in reminders where reminder.completedAt == nil && reminder.remindersEnabled {
            scheduleReminderNudge(reminder: reminder, calendar: calendar, now: now)
        }
    }

    // MARK: - Streak protection

    /// Notify in the evening if a recurring practice hasn't been completed today
    /// and the user has an active streak worth protecting.
    private func scheduleStreakProtection(practice: Practice, calendar: Calendar, now: Date) {
        // Only protect streaks of 2+ days
        guard practice.currentStreak >= 2 && !practice.checkedIn else { return }

        let body = "Your \(practice.currentStreak)-day \(practice.title) streak is still alive. One check-in keeps it going."

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        // Only schedule if reminder time hasn't passed yet today
        if let reminderToday = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now),
           reminderToday > now {
            scheduleNotification(
                id: "streak-\(practice.id)",
                title: practice.title,
                body: body,
                dateComponents: dateComponents
            )
        }
    }

    // MARK: - Reminder nudges

    /// Notify when a reminder is due tomorrow (evening before) and due today (morning of).
    private func scheduleReminderNudge(reminder: Reminder, calendar: Calendar, now: Date) {
        let daysRemaining = reminder.daysRemaining
        let id = reminder.id.uuidString

        if daysRemaining == 1 {
            var dateComponents = DateComponents()
            dateComponents.hour = reminderHour
            dateComponents.minute = reminderMinute

            if let reminderToday = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now),
               reminderToday > now {
                scheduleNotification(
                    id: "due-tomorrow-\(id)",
                    title: reminder.label,
                    body: "\(reminder.label) is tomorrow.",
                    dateComponents: dateComponents
                )
            }
        } else if daysRemaining == 0 {
            var dateComponents = DateComponents()
            dateComponents.hour = 9
            dateComponents.minute = 0

            if let morningToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
               morningToday > now {
                scheduleNotification(
                    id: "due-today-\(id)",
                    title: reminder.label,
                    body: "\(reminder.label) is today.",
                    dateComponents: dateComponents
                )
            }

            var eveningComponents = DateComponents()
            eveningComponents.hour = reminderHour
            eveningComponents.minute = reminderMinute

            if let eveningToday = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now),
               eveningToday > now {
                scheduleNotification(
                    id: "due-today-evening-\(id)",
                    title: reminder.label,
                    body: "\(reminder.label) is today. You still have time.",
                    dateComponents: eveningComponents
                )
            }
        } else if daysRemaining < 0 && daysRemaining >= -3 {
            var dateComponents = DateComponents()
            dateComponents.hour = 9
            dateComponents.minute = 0

            let overdueDays = abs(daysRemaining)
            if let morningToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
               morningToday > now {
                scheduleNotification(
                    id: "overdue-\(id)",
                    title: reminder.label,
                    body: "\(reminder.label) has been waiting for \(overdueDays) day\(overdueDays == 1 ? "" : "s").",
                    dateComponents: dateComponents
                )
            }
        }
    }

    // MARK: - Helper

    private func scheduleNotification(id: String, title: String, body: String, dateComponents: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                Task { @MainActor in
                    AppLogger.shared.error("Notifications", "Failed to schedule: \(error)")
                }
            }
        }
    }
}
