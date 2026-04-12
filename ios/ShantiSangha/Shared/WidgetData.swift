import Foundation

/// Shared data between the main app and widget extension.
/// Both sides use the same App Group UserDefaults.
enum WidgetData {
    static let appGroupId = "group.com.shantisangha.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Mantra

    static var mantra: String? {
        get { defaults?.string(forKey: "widget.mantra") }
        set { defaults?.set(newValue, forKey: "widget.mantra") }
    }

    // MARK: - Practices

    static var practicesDone: Int {
        get { defaults?.integer(forKey: "widget.practicesDone") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget.practicesDone") }
    }

    static var practicesTotal: Int {
        get { defaults?.integer(forKey: "widget.practicesTotal") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget.practicesTotal") }
    }

    // MARK: - Goals

    static var goalsOverdue: Int {
        get { defaults?.integer(forKey: "widget.goalsOverdue") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget.goalsOverdue") }
    }

    static var goalsDueToday: Int {
        get { defaults?.integer(forKey: "widget.goalsDueToday") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget.goalsDueToday") }
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
        mantra: String?,
        practicesDone: Int,
        practicesTotal: Int,
        goalsOverdue: Int,
        goalsDueToday: Int,
        userName: String?
    ) {
        self.mantra = mantra
        self.practicesDone = practicesDone
        self.practicesTotal = practicesTotal
        self.goalsOverdue = goalsOverdue
        self.goalsDueToday = goalsDueToday
        self.userName = userName
        self.lastUpdated = Date()
    }
}
