import Foundation
import SwiftData

/// Local database models for offline-first architecture.
/// These mirror the API types but are persisted in SwiftData.

@Model
class CachedPractice {
    @Attribute(.unique) var id: String
    var title: String
    var currentStreak: Int
    var longestStreak: Int
    var checkedIn: Bool
    var completedToday: Bool?
    var lastSyncedAt: Date
    var hasPendingChanges: Bool

    init(id: String, title: String, currentStreak: Int = 0,
         longestStreak: Int = 0,
         checkedIn: Bool = false, completedToday: Bool? = nil,
         hasPendingChanges: Bool = false) {
        self.id = id
        self.title = title
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.checkedIn = checkedIn
        self.completedToday = completedToday
        self.lastSyncedAt = Date()
        self.hasPendingChanges = hasPendingChanges
    }

    /// Convert to the view-layer Practice type
    func toPractice() -> Practice {
        var practice = Practice.local(
            id: id, title: title,
            currentStreak: currentStreak, longestStreak: longestStreak,
            checkedIn: checkedIn, completedToday: completedToday
        )
        practice.hasPendingChanges = hasPendingChanges
        return practice
    }

    /// Update from an API response
    func update(from practice: Practice) {
        title = practice.title
        currentStreak = practice.currentStreak
        longestStreak = practice.longestStreak
        checkedIn = practice.checkedIn
        completedToday = practice.completedToday
        lastSyncedAt = Date()
        hasPendingChanges = false
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
    var tempId: String?
    var lastAttemptedAt: Date?

    init(method: String, path: String, body: Data? = nil, tempId: String? = nil) {
        self.id = UUID().uuidString
        self.method = method
        self.path = path
        self.body = body
        self.createdAt = Date()
        self.retryCount = 0
        self.tempId = tempId
        self.lastAttemptedAt = nil
    }
}
