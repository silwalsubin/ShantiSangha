import Foundation

/// Shared data between the main app and widget extension.
/// Both sides use the same App Group UserDefaults.
enum WidgetData {
    static let appGroupId = "group.com.shantisangha.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Reflection

    static var reflection: String? {
        get { defaults?.string(forKey: "widget.reflection") }
        set { defaults?.set(newValue, forKey: "widget.reflection") }
    }

    // MARK: - Reminders

    static var remindersOverdue: Int {
        get { defaults?.integer(forKey: "widget.remindersOverdue") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget.remindersOverdue") }
    }

    static var remindersDueToday: Int {
        get { defaults?.integer(forKey: "widget.remindersDueToday") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget.remindersDueToday") }
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
        reflection: String?,
        remindersOverdue: Int,
        remindersDueToday: Int,
        userName: String?
    ) {
        self.reflection = reflection
        self.remindersOverdue = remindersOverdue
        self.remindersDueToday = remindersDueToday
        self.userName = userName
        self.lastUpdated = Date()
    }
}
