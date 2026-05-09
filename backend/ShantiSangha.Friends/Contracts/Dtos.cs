using ShantiSangha.Friends.Models;

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
/// like Country flow from the user's Profile. For local Persons
/// (UserId null), they're set directly by the owner.
public record PersonResponse(
    Guid Id,
    Guid? UserId,
    string DisplayName,
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
/// uses it to gate the chat affordance. `Circles` is the free-form
/// tag set the owner has applied (empty array allowed). `Dates` is
/// the owner-private "important dates" list (birthday, anniversary,
/// day-we-met) sorted by Date ascending.
public record ConnectionResponse(
    Guid Id,
    Guid OwnerUserId,
    Guid PersonId,
    IReadOnlyList<string> Circles,
    string? Nickname,
    string? PrivateNotes,
    Guid? FriendshipId,
    bool Messageable,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    PersonResponse Person,
    IReadOnlyList<ConnectionDateResponse> Dates,
    string? LastMessagePreview,
    DateTime? LastMessageAt,
    int UnreadCount);

/// Single owner-private "important date" attached to a Connection.
/// Order in the parent list is Date ascending. `Recurrence` tells the
/// client whether the date repeats annually (birthday, anniversary)
/// or pins to its absolute calendar slot (moved cities, started job).
public record ConnectionDateResponse(
    Guid Id,
    string Label,
    DateOnly Date,
    ConnectionDateRecurrence Recurrence);

/// Add a new date to a Connection. Label is trimmed; date required.
/// `Recurrence` defaults to `Yearly` — the most common case is
/// birthdays/anniversaries that roll forward each year.
public record AddConnectionDateRequest(
    string Label,
    DateOnly Date,
    ConnectionDateRecurrence Recurrence = ConnectionDateRecurrence.Yearly);

/// Update an existing date on a Connection. All fields required —
/// the iOS edit sheet always submits the full row.
public record UpdateConnectionDateRequest(
    string Label,
    DateOnly Date,
    ConnectionDateRecurrence Recurrence = ConnectionDateRecurrence.Yearly);

// ── Connection attachments (keepsakes: media + files) ───────────────

/// Single attachment (photo, video, PDF, anything) attached to a
/// Connection. `Kind` is server-assigned from `ContentType` so the
/// client can split MEDIA from FILES without trusting itself. Each
/// `DownloadUrl` is a fresh presigned GET that expires shortly after
/// fetch — list again to refresh.
public record ConnectionAttachmentResponse(
    Guid Id,
    Guid ConnectionId,
    string ObjectKey,
    string ContentType,
    long ByteSize,
    string FileName,
    string Kind,
    string? Caption,
    string DownloadUrl,
    DateTime CreatedAt,
    DateTime UpdatedAt);

/// Step 1 of the upload handshake — backend hands back a presigned PUT
/// URL the client uses to ship bytes directly to S3, plus the
/// `objectKey` it should round-trip on commit.
public record CreateConnectionAttachmentUploadResponse(
    string ObjectKey,
    string UploadUrl,
    DateTime UploadUrlExpiresAt);

/// Step 1 request — the client tells us the content type and (a hint
/// at) the file extension so the key gets a friendly suffix. We trust
/// the type for routing/extension purposes only; final classification
/// happens server-side from the actual stored object.
public record CreateConnectionAttachmentUploadRequest(
    string ContentType,
    string? FileName = null);

/// Step 2 — the client confirms the upload landed and tells us what
/// to record. `ByteSize` is verified against S3 metadata server-side
/// to keep clients honest.
public record CommitConnectionAttachmentRequest(
    string ObjectKey,
    string ContentType,
    string FileName,
    string? Caption = null);

/// Caption-only edit. Pass an empty string (or whitespace) to clear.
public record UpdateConnectionAttachmentRequest(string? Caption = null);

/// Creates a local Person + Connection in one call. Backend sets
/// `Person.UserId = NULL` and `Connection.FriendshipId = NULL`. An
/// empty/missing `Circles` array is allowed — the user can label the
/// connection later.
public record CreateConnectionRequest(
    string DisplayName,
    IReadOnlyList<string>? Circles = null,
    string? Nickname = null,
    string? PrivateNotes = null,
    string? PhoneNumber = null,
    string? Email = null,
    string? Country = null,
    string? State = null,
    string? City = null,
    string? Address = null);

/// Updates Connection-overlay fields only. Person fields go through
/// `UpdatePersonRequest`. `Circles` is null = leave alone, [] = clear,
/// otherwise replace. The other fields keep the existing Clear* pattern.
public record UpdateConnectionRequest(
    IReadOnlyList<string>? Circles = null,
    string? Nickname = null,
    string? PrivateNotes = null,
    bool? ClearNickname = null,
    bool? ClearPrivateNotes = null);

/// Updates the underlying Person row (only allowed when caller owns
/// the local Person OR Person.UserId == caller). Same Clear* pattern.
public record UpdatePersonRequest(
    string? DisplayName = null,
    string? PhoneNumber = null,
    string? Email = null,
    string? Country = null,
    string? State = null,
    string? City = null,
    string? Address = null,
    bool? ClearPhoneNumber = null,
    bool? ClearEmail = null,
    bool? ClearCountry = null,
    bool? ClearState = null,
    bool? ClearCity = null,
    bool? ClearAddress = null);
