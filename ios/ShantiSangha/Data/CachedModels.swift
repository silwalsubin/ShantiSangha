import Foundation
import SwiftData

/// Local database models for offline-first architecture.
/// These mirror the API types but are persisted in SwiftData.

@Model
class CachedTask {
    @Attribute(.unique) var id: String
    var title: String
    var type: String  // "Recurring" or "OneTime"
    var currentStreak: Int
    var longestStreak: Int
    var daysRemaining: Int?
    var progress: Int
    var checkedIn: Bool
    var completedToday: Bool?
    var feedbackMessage: String?
    var lastSyncedAt: Date

    init(id: String, title: String, type: String, currentStreak: Int = 0,
         longestStreak: Int = 0, daysRemaining: Int? = nil, progress: Int = 0,
         checkedIn: Bool = false, completedToday: Bool? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.daysRemaining = daysRemaining
        self.progress = progress
        self.checkedIn = checkedIn
        self.completedToday = completedToday
        self.lastSyncedAt = Date()
    }

    /// Convert to the view-layer AppTask type
    func toAppTask() -> AppTask {
        var task = AppTask.local(
            id: id, title: title, type: type,
            currentStreak: currentStreak, longestStreak: longestStreak,
            daysRemaining: daysRemaining, progress: progress,
            checkedIn: checkedIn, completedToday: completedToday
        )
        task.feedbackMessage = feedbackMessage
        return task
    }

    /// Update from an API response
    func update(from task: AppTask) {
        title = task.title
        currentStreak = task.currentStreak
        longestStreak = task.longestStreak
        daysRemaining = task.daysRemaining
        progress = task.progress
        checkedIn = task.checkedIn
        completedToday = task.completedToday
        lastSyncedAt = Date()
    }
}

@Model
class CachedConversation {
    @Attribute(.unique) var id: String
    var title: String
    var lastMessage: String
    var updatedAt: Date

    init(id: String, title: String, lastMessage: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
    }
}

@Model
class SyncQueueItem {
    var id: String
    var method: String
    var path: String
    var body: Data?
    var createdAt: Date
    var retryCount: Int

    init(method: String, path: String, body: Data? = nil) {
        self.id = UUID().uuidString
        self.method = method
        self.path = path
        self.body = body
        self.createdAt = Date()
        self.retryCount = 0
    }
}
