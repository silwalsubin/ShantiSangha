using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Friends.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class FriendsService(
    FriendsDbContext db,
    IProfileQueryService profileQuery,
    IPushNotificationService push,
    FriendsMediaStorage storage,
    ILogger<FriendsService> logger) : IFriendsService
{
    private static readonly TimeSpan InvitationLifetime = TimeSpan.FromDays(7);
    private const int MaxActiveInvitations = 5;
    private const int MaxInvitationsPer24Hours = 10;

    public async Task<List<FriendSummaryResponse>> ListFriendsAsync(Guid userId, CancellationToken ct = default)
    {
        var friendships = await db.Friendships
            .Where(f => f.UserAId == userId || f.UserBId == userId)
            .OrderByDescending(f => f.CreatedAt)
            .ToListAsync(ct);

        if (friendships.Count == 0) return [];

        var friendshipIds = friendships.Select(f => f.Id).ToList();
        var lastMessages = await db.Messages
            .Where(m => friendshipIds.Contains(m.FriendshipId))
            .GroupBy(m => m.FriendshipId)
            .Select(g => g.OrderByDescending(m => m.SentAt).First())
            .ToListAsync(ct);
        var lastMessageMap = lastMessages.ToDictionary(m => m.FriendshipId, m => m);

        var unreadCounts = await db.Messages
            .Where(m => friendshipIds.Contains(m.FriendshipId)
                && m.SenderUserId != userId
                && m.ReadAt == null)
            .GroupBy(m => m.FriendshipId)
            .Select(g => new { FriendshipId = g.Key, Count = g.Count() })
            .ToListAsync(ct);
        var unreadMap = unreadCounts.ToDictionary(u => u.FriendshipId, u => u.Count);

        // Bulk-fetch this viewer's annotations across every friendship in
        // one round-trip so the per-row loop stays O(friends) regardless
        // of how many have nicknames/notes set.
        var annotations = await db.FriendshipAnnotations
            .Where(a => a.OwnerUserId == userId && friendshipIds.Contains(a.FriendshipId))
            .ToDictionaryAsync(a => a.FriendshipId, ct);

        var result = new List<FriendSummaryResponse>(friendships.Count);
        foreach (var f in friendships)
        {
            var friendUserId = f.UserAId == userId ? f.UserBId : f.UserAId;
            var displayName = await profileQuery.GetDisplayNameAsync(friendUserId, ct) ?? "Friend";
            var avatar = await profileQuery.GetAvatarInfoAsync(friendUserId, ct);
            var location = await profileQuery.GetLocationAsync(friendUserId, ct);
            annotations.TryGetValue(f.Id, out var ann);

            string? preview = null;
            DateTime? sentAt = null;
            if (lastMessageMap.TryGetValue(f.Id, out var last))
            {
                preview = BuildPreview(last);
                sentAt = last.SentAt;
            }

            result.Add(new FriendSummaryResponse(
                f.Id,
                friendUserId,
                displayName,
                f.CreatedAt,
                preview,
                sentAt,
                unreadMap.GetValueOrDefault(f.Id, 0),
                avatar.AvatarKey,
                avatar.AvatarUrl,
                ann?.Nickname,
                ann?.PrivateNotes,
                location.Country,
                location.State,
                location.City));
        }
        return result;
    }

    public async Task<FriendSummaryResponse?> GetFriendAsync(Guid userId, Guid friendshipId, CancellationToken ct = default)
    {
        var f = await FindFriendshipForUserAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var friendUserId = f.UserAId == userId ? f.UserBId : f.UserAId;
        var displayName = await profileQuery.GetDisplayNameAsync(friendUserId, ct) ?? "Friend";
        var avatar = await profileQuery.GetAvatarInfoAsync(friendUserId, ct);
        var location = await profileQuery.GetLocationAsync(friendUserId, ct);
        var annotation = await db.FriendshipAnnotations
            .FirstOrDefaultAsync(a => a.FriendshipId == f.Id && a.OwnerUserId == userId, ct);

        var last = await db.Messages
            .Where(m => m.FriendshipId == f.Id)
            .OrderByDescending(m => m.SentAt)
            .FirstOrDefaultAsync(ct);

        var unread = await db.Messages
            .CountAsync(m => m.FriendshipId == f.Id && m.SenderUserId != userId && m.ReadAt == null, ct);

        return new FriendSummaryResponse(
            f.Id, friendUserId, displayName, f.CreatedAt,
            last is not null ? BuildPreview(last) : null,
            last?.SentAt,
            unread,
            avatar.AvatarKey,
            avatar.AvatarUrl,
            annotation?.Nickname,
            annotation?.PrivateNotes,
            location.Country,
            location.State,
            location.City);
    }

    public async Task<CreateInvitationResponse> CreateInvitationAsync(Guid userId, string baseUrl, CancellationToken ct = default)
    {
        var displayName = await profileQuery.GetDisplayNameAsync(userId, ct);
        if (string.IsNullOrWhiteSpace(displayName))
            throw new FriendsServiceException("display_name_required", "Set a display name before inviting people to your circle.");

        var now = DateTime.UtcNow;

        var activeInvites = await db.Invitations
            .CountAsync(i => i.InviterUserId == userId
                && i.AcceptedAt == null
                && i.RevokedAt == null
                && i.ExpiresAt > now, ct);
        if (activeInvites >= MaxActiveInvitations)
            throw new FriendsServiceException("too_many_active_invites",
                $"You already have {activeInvites} active invites. Revoke one before creating another.");

        var dayAgo = now.AddDays(-1);
        var recentCount = await db.Invitations
            .CountAsync(i => i.InviterUserId == userId && i.CreatedAt >= dayAgo, ct);
        if (recentCount >= MaxInvitationsPer24Hours)
            throw new FriendsServiceException("rate_limited",
                "You've created too many invites today. Try again tomorrow.");

        var token = InvitationTokenGenerator.Generate();
        var invitation = new FriendInvitation
        {
            Id = Guid.NewGuid(),
            InviterUserId = userId,
            Token = token,
            CreatedAt = now,
            ExpiresAt = now.Add(InvitationLifetime)
        };
        db.Invitations.Add(invitation);
        await db.SaveChangesAsync(ct);

        return new CreateInvitationResponse(
            invitation.Id, token,
            BuildShareUrl(baseUrl, token),
            BuildDeepLinkUrl(token),
            invitation.ExpiresAt);
    }

    public async Task<List<PendingInvitationResponse>> ListInvitationsAsync(Guid userId, string baseUrl, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var rows = await db.Invitations
            .Where(i => i.InviterUserId == userId
                && i.AcceptedAt == null
                && i.RevokedAt == null
                && i.ExpiresAt > now)
            .OrderByDescending(i => i.CreatedAt)
            .ToListAsync(ct);

        return rows.Select(i => new PendingInvitationResponse(
            i.Id, i.Token,
            BuildShareUrl(baseUrl, i.Token),
            BuildDeepLinkUrl(i.Token),
            i.CreatedAt,
            i.ExpiresAt)).ToList();
    }

    public async Task<bool> RevokeInvitationAsync(Guid userId, Guid invitationId, CancellationToken ct = default)
    {
        var invite = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == invitationId && i.InviterUserId == userId, ct);
        if (invite is null) return false;
        if (invite.RevokedAt is not null || invite.AcceptedAt is not null) return true;

        invite.RevokedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<InvitationPreviewResponse?> PreviewInvitationAsync(Guid userId, string token, CancellationToken ct = default)
    {
        var invite = await db.Invitations.FirstOrDefaultAsync(i => i.Token == token, ct);
        if (invite is null) return null;

        var inviterName = await profileQuery.GetDisplayNameAsync(invite.InviterUserId, ct) ?? "A friend";
        var alreadyFriends = await ExistsFriendshipAsync(invite.InviterUserId, userId, ct);

        return new InvitationPreviewResponse(
            inviterName,
            invite.ExpiresAt < DateTime.UtcNow,
            invite.AcceptedAt is not null || invite.RevokedAt is not null,
            alreadyFriends,
            invite.InviterUserId == userId);
    }

    public async Task<FriendSummaryResponse> AcceptInvitationAsync(Guid userId, string token, CancellationToken ct = default)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        var invite = await db.Invitations.FirstOrDefaultAsync(i => i.Token == token, ct)
            ?? throw new FriendsServiceException("invalid_token", "This invite link is not valid.");

        if (invite.RevokedAt is not null)
            throw new FriendsServiceException("revoked", "This invite has been revoked.");
        if (invite.AcceptedAt is not null)
            throw new FriendsServiceException("already_used", "This invite has already been accepted.");
        if (invite.ExpiresAt < DateTime.UtcNow)
            throw new FriendsServiceException("expired", "This invite has expired.");
        if (invite.InviterUserId == userId)
            throw new FriendsServiceException("self", "You can't accept your own invite.");

        if (await ExistsFriendshipAsync(invite.InviterUserId, userId, ct))
            throw new FriendsServiceException("already_friends", "They're already in your circle.");

        var (a, b) = invite.InviterUserId.CompareTo(userId) < 0
            ? (invite.InviterUserId, userId)
            : (userId, invite.InviterUserId);

        var friendship = new Friendship
        {
            Id = Guid.NewGuid(),
            UserAId = a,
            UserBId = b,
            CreatedAt = DateTime.UtcNow
        };
        db.Friendships.Add(friendship);

        invite.AcceptedAt = DateTime.UtcNow;
        invite.AcceptedByUserId = userId;

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            throw new FriendsServiceException("already_friends", "They're already in your circle.");
        }
        await tx.CommitAsync(ct);

        var inviterName = await profileQuery.GetDisplayNameAsync(invite.InviterUserId, ct) ?? "Friend";
        var accepterName = await profileQuery.GetDisplayNameAsync(userId, ct) ?? "A friend";

        try
        {
            await push.SendAlertPushAsync(invite.InviterUserId,
                title: "Joined your circle",
                body: $"{accepterName} joined your circle.",
                data: new Dictionary<string, string>
                {
                    ["type"] = "friendship_created",
                    ["friendshipId"] = friendship.Id.ToString()
                }, ct: ct);
            await push.SendAlertPushAsync(userId,
                title: "Joined your circle",
                body: $"{inviterName} is now in your circle.",
                data: new Dictionary<string, string>
                {
                    ["type"] = "friendship_created",
                    ["friendshipId"] = friendship.Id.ToString()
                }, ct: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to send friendship_created push for friendship {FriendshipId}", friendship.Id);
        }

        var inviterAvatar = await profileQuery.GetAvatarInfoAsync(invite.InviterUserId, ct);
        var inviterLocation = await profileQuery.GetLocationAsync(invite.InviterUserId, ct);
        return new FriendSummaryResponse(
            friendship.Id, invite.InviterUserId, inviterName,
            friendship.CreatedAt, null, null, 0,
            inviterAvatar.AvatarKey, inviterAvatar.AvatarUrl,
            // No annotations exist yet for a fresh friendship.
            null, null,
            inviterLocation.Country, inviterLocation.State, inviterLocation.City);
    }

    public async Task<FriendSummaryResponse?> UpdateFriendAnnotationsAsync(
        Guid userId,
        Guid friendshipId,
        UpdateFriendAnnotationsRequest request,
        CancellationToken ct = default)
    {
        var f = await FindFriendshipForUserAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var row = await db.FriendshipAnnotations
            .FirstOrDefaultAsync(a => a.FriendshipId == friendshipId && a.OwnerUserId == userId, ct);
        if (row is null)
        {
            row = new FriendshipAnnotation
            {
                FriendshipId = friendshipId,
                OwnerUserId = userId
            };
            db.FriendshipAnnotations.Add(row);
        }

        // Clear-flag wins over the value field — explicit "set to null"
        // beats "leave alone." A null value with no clear flag is a no-op.
        if (request.ClearNickname == true)
        {
            row.Nickname = null;
        }
        else if (request.Nickname is not null)
        {
            var trimmed = request.Nickname.Trim();
            row.Nickname = trimmed.Length == 0 ? null : trimmed;
        }

        if (request.ClearPrivateNotes == true)
        {
            row.PrivateNotes = null;
        }
        else if (request.PrivateNotes is not null)
        {
            // Don't trim notes — preserve whitespace and newlines the user
            // typed. Only collapse a fully-empty submission to null.
            row.PrivateNotes = string.IsNullOrEmpty(request.PrivateNotes) ? null : request.PrivateNotes;
        }

        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        return await GetFriendAsync(userId, friendshipId, ct);
    }

    public async Task<bool> EndFriendshipAsync(Guid userId, Guid friendshipId, CancellationToken ct = default)
    {
        var f = await FindFriendshipForUserAsync(friendshipId, userId, ct);
        if (f is null) return false;

        var messages = await db.Messages.Where(m => m.FriendshipId == f.Id).ToListAsync(ct);
        var mediaKeys = messages.Where(m => m.StorageKey is not null).Select(m => m.StorageKey!).ToList();

        db.Messages.RemoveRange(messages);
        db.Friendships.Remove(f);
        await db.SaveChangesAsync(ct);

        if (mediaKeys.Count > 0)
        {
            try
            {
                await storage.DeleteManyAsync(mediaKeys);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to delete media for ended friendship {FriendshipId}", f.Id);
            }
        }

        return true;
    }

    private async Task<Friendship?> FindFriendshipForUserAsync(Guid friendshipId, Guid userId, CancellationToken ct) =>
        await db.Friendships.FirstOrDefaultAsync(
            f => f.Id == friendshipId && (f.UserAId == userId || f.UserBId == userId), ct);

    private async Task<bool> ExistsFriendshipAsync(Guid userA, Guid userB, CancellationToken ct)
    {
        var (a, b) = userA.CompareTo(userB) < 0 ? (userA, userB) : (userB, userA);
        return await db.Friendships.AnyAsync(f => f.UserAId == a && f.UserBId == b, ct);
    }

    private static string BuildPreview(FriendMessage m) => m.Kind switch
    {
        FriendMessageKind.Text => string.IsNullOrWhiteSpace(m.Body)
            ? "(empty message)"
            : (m.Body.Length > 80 ? m.Body[..80] + "…" : m.Body),
        FriendMessageKind.Image => "(photo)",
        FriendMessageKind.Voice => "(voice message)",
        _ => "(message)"
    };

    private static string BuildShareUrl(string baseUrl, string token) =>
        $"{baseUrl.TrimEnd('/')}/invite/{token}";

    private static string BuildDeepLinkUrl(string token) =>
        $"shantisangha://invite/{token}";
}
