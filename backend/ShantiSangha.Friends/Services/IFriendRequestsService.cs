using ShantiSangha.Friends.Contracts;

namespace ShantiSangha.Friends.Services;

public interface IFriendRequestsService
{
    /// <summary>
    /// Send a direct friend request from `fromUserId` to `toUserId`. Throws
    /// `FriendsServiceException` on validation issues:
    ///   - "self" — can't send to yourself
    ///   - "already_friends" — already in a Friendship together
    ///   - "already_pending" — there's already a Pending row from sender → recipient
    ///   - "user_not_found" — the recipient doesn't exist
    /// On success, persists a Pending FriendRequest row, enqueues an
    /// in-app notification for the recipient, and sends a push.
    /// </summary>
    Task<FriendRequestResponse> SendAsync(Guid fromUserId, Guid toUserId, CancellationToken ct = default);

    /// <summary>
    /// List incoming Pending requests for `userId` — what the recipient
    /// sees in the "you have N requests" surface.
    /// </summary>
    Task<List<FriendRequestResponse>> ListIncomingAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// List outgoing requests from `userId` — Pending only by default,
    /// useful for "I sent X a request, did they accept?".
    /// </summary>
    Task<List<FriendRequestResponse>> ListOutgoingAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Recipient accepts. Atomically: flips the request to Accepted,
    /// creates a Friendship, enqueues a notification + push back to the
    /// original sender. Returns the resulting friendship summary so the
    /// iOS layer can route to the chat view.
    /// </summary>
    Task<FriendSummaryResponse> AcceptAsync(Guid recipientUserId, Guid requestId, CancellationToken ct = default);

    /// <summary>
    /// Recipient declines. The sender is not notified — declines are
    /// silent to avoid social pressure.
    /// </summary>
    Task<bool> DeclineAsync(Guid recipientUserId, Guid requestId, CancellationToken ct = default);

    /// <summary>
    /// Sender cancels their own outgoing request before the recipient
    /// acts. Recipient simply sees the row vanish from their inbox.
    /// </summary>
    Task<bool> CancelAsync(Guid senderUserId, Guid requestId, CancellationToken ct = default);
}
