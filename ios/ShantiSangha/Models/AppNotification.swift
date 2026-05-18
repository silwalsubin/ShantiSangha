import Foundation

/// Mirror of the backend `NotificationResponse` — one in-app notification
/// row. `payload` is a raw JSON string; the iOS view layer decodes per-type
/// (each `Type` value has its own payload schema).
struct AppNotification: Codable, Identifiable, Equatable {
    let id: UUID
    let type: String
    let payload: String
    let createdAt: String
    let viewedAt: String?
}

struct NotificationListResponse: Codable, Equatable {
    let unreadCount: Int
    let notifications: [AppNotification]
}

struct UnreadCountResponse: Codable, Equatable {
    let unreadCount: Int
}

// MARK: - Per-type payload shapes

/// Payload of `type == "friend_request_accepted"`. Lets the sender's
/// inbox surface "X accepted your request" with a tap-through to the
/// new friendship's chat.
struct FriendRequestAcceptedPayload: Codable {
    let requestId: UUID
    let friendshipId: UUID
    let byUserId: UUID
    let byDisplayName: String
    let byAvatarUrl: String?
}

/// Payload of `type == "reminder_shared"`. Lands in the bell inbox when
/// the reminder's owner adds the viewer as a collaborator. Tap routes
/// the user to Home where the new shared row is now visible.
struct ReminderSharedPayload: Codable {
    let reminderId: UUID
    let reminderLabel: String
    let byUserId: UUID
    let byDisplayName: String
    let byAvatarUrl: String?
}

/// Mirror of the backend `FriendRequestResponse` — used by the inbox
/// when it needs to refresh a request's state (e.g., after accept) or by
/// outgoing-request screens.
struct FriendRequestSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let status: String
    let createdAt: String
    let respondedAt: String?
    let otherUserDisplayName: String
    let otherUserAvatarKey: String?
    let otherUserAvatarUrl: String?
}
