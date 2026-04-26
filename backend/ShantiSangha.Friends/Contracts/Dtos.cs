namespace ShantiSangha.Friends.Contracts;

public record FriendSummaryResponse(
    Guid FriendshipId,
    Guid FriendUserId,
    string DisplayName,
    DateTime FriendshipCreatedAt,
    string? LastMessagePreview,
    DateTime? LastMessageAt,
    int UnreadCount,
    string? AvatarKey,
    string? AvatarUrl);

public record CreateInvitationResponse(
    Guid InvitationId,
    string Token,
    string ShareUrl,
    string DeepLinkUrl,
    DateTime ExpiresAt);

public record PendingInvitationResponse(
    Guid InvitationId,
    string Token,
    string ShareUrl,
    string DeepLinkUrl,
    DateTime CreatedAt,
    DateTime ExpiresAt);

public record InvitationPreviewResponse(
    string InviterDisplayName,
    bool TokenExpired,
    bool TokenAlreadyUsed,
    bool AlreadyFriends,
    bool IsOwnInvite);

public record AcceptInvitationRequest(string Token);

public record FriendMessageResponse(
    Guid Id,
    Guid FriendshipId,
    Guid SenderUserId,
    string Kind,
    string? Body,
    string? MediaUrl,
    int? DurationMs,
    DateTime SentAt,
    DateTime? ReadAt);

public record SendTextMessageRequest(string Body);

public record CreateMediaUploadResponse(
    string ObjectKey,
    string UploadUrl,
    DateTime UploadUrlExpiresAt);

public record CommitMediaMessageRequest(
    string ObjectKey,
    int? DurationMs);

// ── FriendRequest (direct in-app, distinct from token-based FriendInvitation) ──

public record SendFriendRequestRequest(Guid ToUserId);

public record FriendRequestResponse(
    Guid Id,
    Guid FromUserId,
    Guid ToUserId,
    string Status,
    DateTime CreatedAt,
    DateTime? RespondedAt,
    string OtherUserDisplayName,
    string? OtherUserAvatarKey,
    string? OtherUserAvatarUrl);
