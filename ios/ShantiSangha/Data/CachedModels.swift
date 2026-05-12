import Foundation
import SwiftData

/// Local database models for offline-first architecture.
/// These mirror the API types but are persisted in SwiftData.

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
