import Foundation

/// Typed wrapper around the in-app notifications + friend-requests API.
/// Consolidates both the inbox list/mark-viewed/unread-count calls AND
/// the friend-request CRUD since they're conceptually one feature on the
/// iOS side (requests show up as notifications and the inbox renders
/// them with accept/decline inline).
enum NotificationsAPI {
    // MARK: - Inbox

    static func list(page: Int = 1, pageSize: Int = 30) async throws -> NotificationListResponse {
        try await ApiService.shared.get("/notifications?page=\(page)&pageSize=\(pageSize)")
    }

    static func unreadCount() async throws -> UnreadCountResponse {
        try await ApiService.shared.get("/notifications/unread-count")
    }

    /// Bulk-stamp all unread notifications as viewed for this user. The
    /// iOS layer fires this when the inbox is opened; backend returns a
    /// trivial `{ updated: N }` body we don't bother decoding.
    static func markAllViewed() async throws {
        struct Empty: Encodable {}
        let _: EmptyResponse = try await ApiService.shared.post("/notifications/mark-viewed", body: Empty())
    }

    // MARK: - Friend requests

    struct SendFriendRequestBody: Encodable { let toUserId: UUID }
    static func sendFriendRequest(toUserId: UUID) async throws -> FriendRequestSummary {
        try await ApiService.shared.post(
            "/friends/requests",
            body: SendFriendRequestBody(toUserId: toUserId))
    }

    static func listIncomingRequests() async throws -> [FriendRequestSummary] {
        try await ApiService.shared.get("/friends/requests/incoming")
    }

    static func listOutgoingRequests() async throws -> [FriendRequestSummary] {
        try await ApiService.shared.get("/friends/requests/outgoing")
    }

    /// Accepts a request — backend returns the resulting FriendSummary
    /// so the iOS layer can route directly into the new chat without a
    /// follow-up /friends fetch.
    static func acceptRequest(_ requestId: UUID) async throws -> FriendSummary {
        try await ApiService.shared.post("/friends/requests/\(requestId.uuidString.lowercased())/accept")
    }

    static func declineRequest(_ requestId: UUID) async throws {
        let _: EmptyResponse = try await ApiService.shared.post("/friends/requests/\(requestId.uuidString.lowercased())/decline")
    }

    static func cancelRequest(_ requestId: UUID) async throws {
        try await ApiService.shared.delete("/friends/requests/\(requestId.uuidString.lowercased())")
    }
}
