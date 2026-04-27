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
    /// Viewer-private overlay: a label this user has chosen for the friend.
    /// Replaces `displayName` everywhere in this user's UI when non-empty.
    /// The friend never sees it.
    let nickname: String?
    /// Viewer-private freeform notes about the friend. Only this user can
    /// read them; backend filters by `OwnerUserId` server-side.
    let privateNotes: String?
    let country: String?
    let state: String?
    let city: String?

    var id: UUID { friendshipId }

    /// What we render anywhere a friend's name shows up. Falls back to the
    /// real display name when the user hasn't set a nickname.
    var displayLabel: String {
        if let n = nickname?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return displayName
    }

    /// Human-readable location for the profile page header. Drops empty
    /// fields and joins what's left with commas — same shape as
    /// `UserSearchResult.locationString`.
    var locationString: String? {
        let parts = [city, state, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Mirror of the backend `UpdateFriendAnnotationsRequest`. `clear*` flags
/// disambiguate "leave this field alone" (null value) from "set it to
/// null" (clear flag = true). Same pattern as `UpdateMeRequest`.
struct UpdateFriendAnnotationsRequest: Encodable {
    var nickname: String? = nil
    var privateNotes: String? = nil
    var clearNickname: Bool? = nil
    var clearPrivateNotes: Bool? = nil
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
    /// Reaction roll-ups by emoji. Optional so older cached payloads
    /// (saved before reactions shipped) decode cleanly.
    let reactions: [FriendMessageReactionSummary]?

    var isDeleted: Bool { deletedAt != nil }
    var isEdited:  Bool { editedAt != nil && deletedAt == nil }
}

struct FriendMessageReactionSummary: Codable, Equatable, Identifiable {
    let emoji: String
    let byUserIds: [UUID]

    var count: Int { byUserIds.count }
    var id: String { emoji }

    func isMine(currentUserId: UUID?) -> Bool {
        guard let me = currentUserId else { return false }
        return byUserIds.contains(me)
    }
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
