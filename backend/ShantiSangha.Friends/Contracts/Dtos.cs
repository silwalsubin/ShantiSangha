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
    string? AvatarUrl,
    string? Nickname,
    string? PrivateNotes,
    string? Country,
    string? State,
    string? City);

/// Per-viewer overlay: A's nickname/notes for B are independent of B's
/// for A. `Clear*` flags follow the Identity `UpdateMeRequest` pattern —
/// null on a value field means "leave unchanged"; clear-flag = true
/// means "set to NULL". This disambiguates "I didn't send this field"
/// from "I want this cleared."
public record UpdateFriendAnnotationsRequest(
    string? Nickname = null,
    string? PrivateNotes = null,
    bool? ClearNickname = null,
    bool? ClearPrivateNotes = null);

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
    Guid ConversationId,           // group-ready alias; equals FriendshipId for 1:1
    Guid SenderUserId,
    Guid? ReplyToMessageId,
    FriendMessageReplyPreview? ReplyPreview,
    string Kind,
    string? Body,
    string? MediaUrl,
    int? DurationMs,
    DateTime SentAt,
    DateTime? ReadAt,
    DateTime? EditedAt,
    DateTime? DeletedAt,
    List<FriendMessageReactionSummary> Reactions);

/// <summary>One emoji's roll-up for a message: who reacted, by user
/// id. Clients derive `Count` from the list and check membership of
/// their own user id to flag whether the caller's pill should render
/// as "mine". Same payload serves REST + realtime broadcast (the hub
/// fans the same JSON to every subscriber).</summary>
public record FriendMessageReactionSummary(
    string Emoji,
    List<Guid> ByUserIds);

public record AddReactionRequest(string Emoji);

public record FriendMessageReplyPreview(
    Guid Id,
    Guid SenderUserId,
    string Kind,
    string? Body,
    bool IsDeleted);

public record SendTextMessageRequest(string Body, Guid? ReplyToMessageId = null);
public record EditTextMessageRequest(string Body);

public record CreateMediaUploadResponse(
    string ObjectKey,
    string UploadUrl,
    DateTime UploadUrlExpiresAt);

public record CommitMediaMessageRequest(
    string ObjectKey,
    int? DurationMs,
    Guid? ReplyToMessageId = null);

public record MarkMessagesReadRequest(Guid LastMessageId);

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

// ── Circle: Person + Connection ─────────────────────────────────────

/// The "who" — biographical data the owner can see about a person in
/// their circle. For linked Persons (UserId set), biographical fields
/// like BirthDate/Country flow from the user's Profile. For local
/// Persons (UserId null), they're set directly by the owner.
public record PersonResponse(
    Guid Id,
    Guid? UserId,
    string DisplayName,
    DateOnly? BirthDate,
    string? BirthTime,
    string? BirthPlace,
    string? PhoneNumber,
    string? Email,
    string? Country,
    string? State,
    string? City,
    string? Address,
    string? AvatarKey,
    string? AvatarUrl);

/// The "how I know them" — owner-scoped relationship overlay. The
/// embedded `Person` carries identity. `Messageable` is true iff
/// `Person.UserId` is set AND `FriendshipId` is set; the iOS layer
/// uses it to gate the chat affordance.
public record ConnectionResponse(
    Guid Id,
    Guid OwnerUserId,
    Guid PersonId,
    string RelationType,
    string? CustomRelationLabel,
    string? Nickname,
    string? PrivateNotes,
    Guid? FriendshipId,
    bool Messageable,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    PersonResponse Person,
    string? LastMessagePreview,
    DateTime? LastMessageAt,
    int UnreadCount);

/// Creates a local Person + Connection in one call. Backend sets
/// `Person.UserId = NULL` and `Connection.FriendshipId = NULL`.
public record CreateConnectionRequest(
    string DisplayName,
    string RelationType,
    string? CustomRelationLabel = null,
    string? Nickname = null,
    string? PrivateNotes = null,
    DateOnly? BirthDate = null,
    string? BirthTime = null,
    string? BirthPlace = null,
    string? PhoneNumber = null,
    string? Email = null,
    string? Country = null,
    string? State = null,
    string? City = null,
    string? Address = null);

/// Updates Connection-overlay fields only. Person fields go through
/// `UpdatePersonRequest`. Same Clear* pattern as the Identity service:
/// null value = leave alone, clear-flag = true = set to null.
public record UpdateConnectionRequest(
    string? RelationType = null,
    string? CustomRelationLabel = null,
    string? Nickname = null,
    string? PrivateNotes = null,
    bool? ClearCustomRelationLabel = null,
    bool? ClearNickname = null,
    bool? ClearPrivateNotes = null);

/// Updates the underlying Person row (only allowed when caller owns
/// the local Person OR Person.UserId == caller). Same Clear* pattern.
public record UpdatePersonRequest(
    string? DisplayName = null,
    DateOnly? BirthDate = null,
    string? BirthTime = null,
    string? BirthPlace = null,
    string? PhoneNumber = null,
    string? Email = null,
    string? Country = null,
    string? State = null,
    string? City = null,
    string? Address = null,
    bool? ClearBirthDate = null,
    bool? ClearBirthTime = null,
    bool? ClearBirthPlace = null,
    bool? ClearPhoneNumber = null,
    bool? ClearEmail = null,
    bool? ClearCountry = null,
    bool? ClearState = null,
    bool? ClearCity = null,
    bool? ClearAddress = null);
