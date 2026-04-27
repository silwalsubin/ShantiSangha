using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class FriendRequestsService(
    FriendsDbContext db,
    IProfileQueryService profileQuery,
    INotificationService notifications,
    IPushNotificationService push,
    ILogger<FriendRequestsService> logger) : IFriendRequestsService
{
    public async Task<FriendRequestResponse> SendAsync(Guid fromUserId, Guid toUserId, CancellationToken ct = default)
    {
        if (fromUserId == toUserId)
            throw new FriendsServiceException("self", "You can't invite yourself.");

        // Recipient must exist — DisplayName check via the Identity
        // module's profile query is a cheap proxy for "user exists with a
        // profile" (we don't expose a generic "user exists" endpoint).
        var recipientName = await profileQuery.GetDisplayNameAsync(toUserId, ct);
        if (string.IsNullOrWhiteSpace(recipientName))
            throw new FriendsServiceException("user_not_found", "We couldn't find that user.");

        // Already friends? Use canonical-pair ordering to match how the
        // Friendship table stores rows.
        var (a, b) = fromUserId.CompareTo(toUserId) < 0
            ? (fromUserId, toUserId)
            : (toUserId, fromUserId);
        var alreadyFriends = await db.Friendships.AnyAsync(f => f.UserAId == a && f.UserBId == b, ct);
        if (alreadyFriends)
            throw new FriendsServiceException("already_friends", "They're already in your circle.");

        // Already a Pending request from this sender to this recipient?
        // We allow re-sends after a Decline (the old row stays in the
        // Declined state; a fresh Pending row is created).
        var existing = await db.Requests
            .Where(r => r.FromUserId == fromUserId
                && r.ToUserId == toUserId
                && r.Status == FriendRequestStatus.Pending)
            .FirstOrDefaultAsync(ct);
        if (existing is not null)
            throw new FriendsServiceException("already_pending", "You've already sent them an invite.");

        var request = new FriendRequest
        {
            Id = Guid.NewGuid(),
            FromUserId = fromUserId,
            ToUserId = toUserId,
            Status = FriendRequestStatus.Pending,
            CreatedAt = DateTime.UtcNow
        };
        db.Requests.Add(request);
        await db.SaveChangesAsync(ct);

        var senderName = await profileQuery.GetDisplayNameAsync(fromUserId, ct) ?? "Someone";

        // Pending friend requests intentionally do NOT land in the bell
        // inbox — the Friends tab's "REQUESTS RECEIVED" card is the one
        // source of truth, queried via /friends/requests/incoming. This
        // avoids duplicate inbox rows when a request is cancelled and
        // re-sent (the inbox would carry orphan rows it has no way to
        // resolve). Terminal events like `friend_request_accepted` still
        // do go through the inbox.
        //
        // Lock-screen push still fires so the recipient sees something
        // when the app is closed. The silent-push variant tells iOS to
        // refresh the Friends-tab badge service (FriendsBadgeService),
        // not the bell inbox.
        try
        {
            await push.SendAlertPushAsync(
                userId: toUserId,
                title: "New invite",
                body: $"{senderName} wants to join your circle.",
                data: new Dictionary<string, string>
                {
                    ["type"] = "friend_request_received",
                    ["requestId"] = request.Id.ToString()
                },
                badge: null,
                ct: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to send friend_request_received push for request {RequestId}", request.Id);
        }

        return await ProjectAsync(request, viewerUserId: fromUserId, ct: ct);
    }

    public async Task<List<FriendRequestResponse>> ListIncomingAsync(Guid userId, CancellationToken ct = default)
    {
        var rows = await db.Requests
            .Where(r => r.ToUserId == userId && r.Status == FriendRequestStatus.Pending)
            .OrderByDescending(r => r.CreatedAt)
            .ToListAsync(ct);

        var result = new List<FriendRequestResponse>(rows.Count);
        foreach (var r in rows)
            result.Add(await ProjectAsync(r, viewerUserId: userId, ct));
        return result;
    }

    public async Task<List<FriendRequestResponse>> ListOutgoingAsync(Guid userId, CancellationToken ct = default)
    {
        var rows = await db.Requests
            .Where(r => r.FromUserId == userId && r.Status == FriendRequestStatus.Pending)
            .OrderByDescending(r => r.CreatedAt)
            .ToListAsync(ct);

        var result = new List<FriendRequestResponse>(rows.Count);
        foreach (var r in rows)
            result.Add(await ProjectAsync(r, viewerUserId: userId, ct));
        return result;
    }

    public async Task<FriendSummaryResponse> AcceptAsync(Guid recipientUserId, Guid requestId, CancellationToken ct = default)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        var request = await db.Requests.FirstOrDefaultAsync(r => r.Id == requestId, ct)
            ?? throw new FriendsServiceException("not_found", "Invite not found.");

        if (request.ToUserId != recipientUserId)
            throw new FriendsServiceException("forbidden", "Only the recipient can accept this request.");
        if (request.Status != FriendRequestStatus.Pending)
            throw new FriendsServiceException("not_pending", "This request is no longer pending.");

        // Race: maybe they became friends through a parallel link-token
        // accept while this request was still pending. Detect and resolve
        // gracefully — flip the request to Accepted but skip the dup row.
        var (a, b) = request.FromUserId.CompareTo(recipientUserId) < 0
            ? (request.FromUserId, recipientUserId)
            : (recipientUserId, request.FromUserId);

        var existing = await db.Friendships.FirstOrDefaultAsync(f => f.UserAId == a && f.UserBId == b, ct);
        Friendship friendship;
        if (existing is null)
        {
            friendship = new Friendship
            {
                Id = Guid.NewGuid(),
                UserAId = a,
                UserBId = b,
                CreatedAt = DateTime.UtcNow
            };
            db.Friendships.Add(friendship);
        }
        else
        {
            friendship = existing;
        }

        request.Status = FriendRequestStatus.Accepted;
        request.RespondedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        var fromName = await profileQuery.GetDisplayNameAsync(request.FromUserId, ct) ?? "Friend";
        var recipientName = await profileQuery.GetDisplayNameAsync(recipientUserId, ct) ?? "your friend";
        var recipientAvatar = await profileQuery.GetAvatarInfoAsync(recipientUserId, ct);

        // Notify the original sender that their request was accepted.
        try
        {
            await notifications.EnqueueAsync(
                recipientUserId: request.FromUserId,
                type: "friend_request_accepted",
                payload: new
                {
                    requestId = request.Id,
                    friendshipId = friendship.Id,
                    byUserId = recipientUserId,
                    byDisplayName = recipientName,
                    byAvatarUrl = recipientAvatar.AvatarUrl
                },
                ct: ct);

            // Badge for the original sender — current unread count after
            // the new accepted-row was just enqueued. Same pattern as the
            // friend_request_received path: query AFTER enqueue so the new
            // row is included, keeping home-screen + bell badges aligned.
            int senderBadge;
            try { senderBadge = await notifications.GetUnreadCountAsync(request.FromUserId, ct); }
            catch { senderBadge = 1; }

            await push.SendAlertPushAsync(
                userId: request.FromUserId,
                title: "Joined your circle",
                body: $"{recipientName} joined your circle.",
                data: new Dictionary<string, string>
                {
                    ["type"] = "friend_request_accepted",
                    ["friendshipId"] = friendship.Id.ToString()
                },
                badge: senderBadge,
                ct: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to notify sender of accepted friend request {RequestId}", request.Id);
        }

        // Build the FriendSummaryResponse the iOS layer expects so it can
        // route directly to the chat view without re-fetching.
        var avatar = await profileQuery.GetAvatarInfoAsync(request.FromUserId, ct);
        var location = await profileQuery.GetLocationAsync(request.FromUserId, ct);
        return new FriendSummaryResponse(
            friendship.Id,
            request.FromUserId,
            fromName,
            friendship.CreatedAt,
            null,
            null,
            0,
            avatar.AvatarKey,
            avatar.AvatarUrl,
            // No annotations for a freshly-accepted request.
            null, null,
            location.Country, location.State, location.City);
    }

    public async Task<bool> DeclineAsync(Guid recipientUserId, Guid requestId, CancellationToken ct = default)
    {
        var request = await db.Requests.FirstOrDefaultAsync(r => r.Id == requestId, ct);
        if (request is null) return false;
        if (request.ToUserId != recipientUserId)
            throw new FriendsServiceException("forbidden", "Only the recipient can decline this request.");
        if (request.Status != FriendRequestStatus.Pending) return true;  // idempotent

        request.Status = FriendRequestStatus.Declined;
        request.RespondedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        // Sender is not notified — declines are silent to avoid pressure.
        return true;
    }

    public async Task<bool> CancelAsync(Guid senderUserId, Guid requestId, CancellationToken ct = default)
    {
        var request = await db.Requests.FirstOrDefaultAsync(r => r.Id == requestId, ct);
        if (request is null) return false;
        if (request.FromUserId != senderUserId)
            throw new FriendsServiceException("forbidden", "Only the sender can cancel this request.");
        if (request.Status != FriendRequestStatus.Pending) return true;  // idempotent

        request.Status = FriendRequestStatus.Cancelled;
        request.RespondedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    /// <summary>
    /// Build a FriendRequestResponse, enriching with the OTHER party's
    /// display name + avatar. From the recipient's perspective the "other"
    /// is the sender; from the sender's perspective the "other" is the
    /// recipient. `viewerUserId` selects which side is "other".
    /// </summary>
    private async Task<FriendRequestResponse> ProjectAsync(FriendRequest r, Guid viewerUserId, CancellationToken ct)
    {
        var otherUserId = r.FromUserId == viewerUserId ? r.ToUserId : r.FromUserId;
        var otherName = await profileQuery.GetDisplayNameAsync(otherUserId, ct) ?? "User";
        var otherAvatar = await profileQuery.GetAvatarInfoAsync(otherUserId, ct);
        return new FriendRequestResponse(
            r.Id,
            r.FromUserId,
            r.ToUserId,
            r.Status.ToString(),
            r.CreatedAt,
            r.RespondedAt,
            otherName,
            otherAvatar.AvatarKey,
            otherAvatar.AvatarUrl);
    }
}
