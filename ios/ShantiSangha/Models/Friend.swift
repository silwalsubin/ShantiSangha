import Foundation

struct FriendSummary: Codable, Identifiable, Equatable, Hashable {
    let friendshipId: UUID
    let friendUserId: UUID
    let displayName: String
    let friendshipCreatedAt: String
    let lastMessagePreview: String?
    let lastMessageAt: String?
    let unreadCount: Int
    /// Stable S3 key for the friend's avatar — round-tripped, not displayed.
    let avatarKey: String?
    /// Short-lived presigned download URL the iOS layer feeds into
    /// `SacredAvatar`. Backend regenerates on every list/refresh; treat as
    /// read-only and refetch the friend list to get a new one if expired.
    let avatarUrl: String?

    var id: UUID { friendshipId }
}

enum FriendMessageKind: String, Codable {
    case text = "Text"
    case image = "Image"
    case voice = "Voice"
}

struct FriendMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let friendshipId: UUID
    /// Group-ready alias; equals `friendshipId` for 1:1 chat. Future
    /// group messages will keep the same wire shape, just with a
    /// different `conversationId` namespace.
    let conversationId: UUID
    let senderUserId: UUID
    let replyToMessageId: UUID?
    let replyPreview: FriendMessageReplyPreview?
    let kind: FriendMessageKind
    let body: String?
    let mediaUrl: String?
    let durationMs: Int?
    let sentAt: String
    let readAt: String?
    let editedAt: String?
    let deletedAt: String?

    var isDeleted: Bool { deletedAt != nil }
    var isEdited:  Bool { editedAt != nil && deletedAt == nil }
}

struct FriendMessageReplyPreview: Codable, Equatable {
    let id: UUID
    let senderUserId: UUID
    let kind: FriendMessageKind
    let body: String?
    let isDeleted: Bool
}

struct CreateInvitationResponse: Codable {
    let invitationId: UUID
    let token: String
    let shareUrl: String
    let deepLinkUrl: String
    let expiresAt: String
}

struct PendingInvitation: Codable, Identifiable {
    let invitationId: UUID
    let token: String
    let shareUrl: String
    let deepLinkUrl: String
    let createdAt: String
    let expiresAt: String

    var id: UUID { invitationId }
}

struct InvitationPreview: Codable {
    let inviterDisplayName: String
    let tokenExpired: Bool
    let tokenAlreadyUsed: Bool
    let alreadyFriends: Bool
    let isOwnInvite: Bool
}

struct CreateMediaUploadResponse: Codable {
    let objectKey: String
    let uploadUrl: String
    let uploadUrlExpiresAt: String
}

enum FriendsDates {
    private static let formatters: [ISO8601DateFormatter] = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFractional, plain]
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
