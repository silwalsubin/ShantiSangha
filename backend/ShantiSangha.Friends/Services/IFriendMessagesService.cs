using ShantiSangha.Friends.Contracts;

namespace ShantiSangha.Friends.Services;

public interface IFriendMessagesService
{
    Task<List<FriendMessageResponse>?> ListMessagesAsync(
        Guid userId, Guid friendshipId, DateTime? before, int limit, CancellationToken ct = default);

    /// Lists ONLY media messages (Image + Voice) for the friendship,
    /// newest first, paginated by `before` cursor on `SentAt`. Used by
    /// the per-Connection "Chat Media & Files" archive screen.
    /// Skips soft-deleted rows so they don't crowd the archive UI.
    /// Returns null when the friendship is missing or the caller isn't
    /// a member.
    Task<List<FriendMessageResponse>?> ListMediaMessagesAsync(
        Guid userId, Guid friendshipId, DateTime? before, int limit, CancellationToken ct = default);

    Task<FriendMessageResponse?> SendTextAsync(
        Guid userId, Guid friendshipId, string body, Guid? replyToMessageId = null, CancellationToken ct = default);

    Task<CreateMediaUploadResponse?> CreateImageUploadAsync(
        Guid userId, Guid friendshipId, string contentType, CancellationToken ct = default);

    Task<CreateMediaUploadResponse?> CreateVoiceUploadAsync(
        Guid userId, Guid friendshipId, string contentType, CancellationToken ct = default);

    Task<FriendMessageResponse?> CommitImageMessageAsync(
        Guid userId, Guid friendshipId, CommitMediaMessageRequest req, CancellationToken ct = default);

    Task<FriendMessageResponse?> CommitVoiceMessageAsync(
        Guid userId, Guid friendshipId, CommitMediaMessageRequest req, CancellationToken ct = default);

    Task<bool> MarkReadAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default);

    Task<bool> MarkReadThroughAsync(
        Guid userId, Guid friendshipId, Guid lastMessageId, CancellationToken ct = default);

    /// <summary>Sender-only edit of a Text message within 15 min of send.
    /// Throws FriendsServiceException with code:
    ///   - "not_found" if message or friendship missing
    ///   - "forbidden" if caller is not the sender
    ///   - "wrong_kind" if not a Text message (can't edit media)
    ///   - "edit_window_expired" past the 15-minute window
    ///   - "already_deleted" if message has been deleted
    /// On success, returns the updated row and broadcasts a
    /// `message_edited` realtime event to the conversation.</summary>
    Task<FriendMessageResponse?> EditTextAsync(
        Guid userId, Guid friendshipId, Guid messageId, string newBody, CancellationToken ct = default);

    /// <summary>Sender-only soft delete of a message. No time window —
    /// senders can delete their own messages whenever. Idempotent: a
    /// re-delete returns the existing row. On success, returns the row
    /// with `DeletedAt` set, blanks `Body` and removes media from S3,
    /// and broadcasts a `message_deleted` realtime event.</summary>
    Task<FriendMessageResponse?> DeleteAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default);

    /// <summary>Set or replace the caller's reaction emoji on a message.
    /// Composite PK on (MessageId, UserId) means re-reacting with a new
    /// emoji upserts to that emoji — one reaction per user per message.
    /// Idempotent: reacting with the same emoji again is a no-op.
    /// Broadcasts a `message_reactions_changed` realtime event with the
    /// updated reaction list.</summary>
    Task<FriendMessageResponse?> ReactAsync(
        Guid userId, Guid friendshipId, Guid messageId, string emoji, CancellationToken ct = default);

    /// <summary>Remove the caller's reaction from a message. Idempotent:
    /// removing a reaction that doesn't exist is a no-op. Broadcasts a
    /// `message_reactions_changed` event when something actually changed.</summary>
    Task<FriendMessageResponse?> UnreactAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default);
}
