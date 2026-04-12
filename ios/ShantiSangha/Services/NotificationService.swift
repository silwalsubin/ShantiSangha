import Foundation
import UserNotifications

/// Schedules local notifications for streak protection and commitment reminders.
/// All notifications are local — no server push infrastructure needed.
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "notificationsEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notificationsEnabled") }
    }

    @Published var reminderHour: Int = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 20 {
        didSet { UserDefaults.standard.set(reminderHour, forKey: "reminderHour") }
    }

    @Published var reminderMinute: Int = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(reminderMinute, forKey: "reminderMinute") }
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

    // MARK: - Schedule all notifications based on current tasks

    func reschedule(tasks: [AppTask]) {
        guard isEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        center.removeAllPendingNotificationRequests()

        let calendar = Calendar.current
        let now = Date()

        for task in tasks {
            if task.type == .recurring {
                scheduleStreakProtection(task: task, calendar: calendar, now: now)
            } else if task.type == .oneTime && task.completedAt == nil {
                scheduleCommitmentReminders(task: task, calendar: calendar, now: now)
            }
        }
    }

    // MARK: - Streak protection

    /// Notify in the evening if a recurring task hasn't been completed today
    /// and the user has an active streak worth protecting.
    private func scheduleStreakProtection(task: AppTask, calendar: Calendar, now: Date) {
        // Only protect streaks of 2+ days
        guard task.currentStreak >= 2 && !task.checkedIn else { return }

        let body = "Your \(task.currentStreak)-day \(task.title) streak is still alive. One check-in keeps it going."

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        // Only schedule if reminder time hasn't passed yet today
        if let reminderToday = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now),
           reminderToday > now {
            scheduleNotification(
                id: "streak-\(task.id)",
                title: task.title,
                body: body,
                dateComponents: dateComponents
            )
        }
    }

    // MARK: - Commitment due reminders

    /// Notify when a commitment is due tomorrow (evening before) and due today (morning of).
    private func scheduleCommitmentReminders(task: AppTask, calendar: Calendar, now: Date) {
        guard let daysRemaining = task.daysRemaining else { return }

        if daysRemaining == 1 {
            // Due tomorrow — remind this evening
            var dateComponents = DateComponents()
            dateComponents.hour = reminderHour
            dateComponents.minute = reminderMinute

            if let reminderToday = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now),
               reminderToday > now {
                scheduleNotification(
                    id: "due-tomorrow-\(task.id)",
                    title: task.title,
                    body: "\(task.title) is due tomorrow.",
                    dateComponents: dateComponents
                )
            }
        } else if daysRemaining == 0 {
            // Due today — remind in the morning (9 AM)
            var dateComponents = DateComponents()
            dateComponents.hour = 9
            dateComponents.minute = 0

            if let morningToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
               morningToday > now {
                scheduleNotification(
                    id: "due-today-\(task.id)",
                    title: task.title,
                    body: "\(task.title) is due today.",
                    dateComponents: dateComponents
                )
            }

            // Also remind in the evening if still not done
            var eveningComponents = DateComponents()
            eveningComponents.hour = reminderHour
            eveningComponents.minute = reminderMinute

            if let eveningToday = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now),
               eveningToday > now {
                scheduleNotification(
                    id: "due-today-evening-\(task.id)",
                    title: task.title,
                    body: "\(task.title) is due today. You still have time.",
                    dateComponents: eveningComponents
                )
            }
        } else if daysRemaining < 0 && daysRemaining >= -3 {
            // Carried over (up to 3 days) — gentle morning reminder
            var dateComponents = DateComponents()
            dateComponents.hour = 9
            dateComponents.minute = 0

            let overdueDays = abs(daysRemaining)
            if let morningToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
               morningToday > now {
                scheduleNotification(
                    id: "overdue-\(task.id)",
                    title: task.title,
                    body: "\(task.title) has been waiting for \(overdueDays) day\(overdueDays == 1 ? "" : "s").",
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
                AppLogger.shared.error("Notifications", "Failed to schedule: \(error)")
            }
        }
    }
}
