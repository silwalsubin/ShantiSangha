using Microsoft.EntityFrameworkCore;
using ShantiSangha.Friends.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

/// <summary>
/// Treats each Friendship row as a 2-member conversation. For v1 every
/// chat is 1:1, so `conversationId == friendship.Id` and the membership
/// answer is simply "are you UserAId or UserBId on that row?".
///
/// When groups land, a sibling implementation in a Groups module will
/// answer for groupId-shaped conversation ids; we'll register both via
/// a chained service-locator that asks each in turn.
/// </summary>
public class FriendshipMembershipService(FriendsDbContext db) : IConversationMembershipService
{
    public async Task<HashSet<Guid>> GetMembersAsync(Guid conversationId, CancellationToken ct = default)
    {
        var f = await db.Friendships
            .Where(x => x.Id == conversationId)
            .Select(x => new { x.UserAId, x.UserBId })
            .FirstOrDefaultAsync(ct);

        return f is null
            ? new HashSet<Guid>()
            : new HashSet<Guid> { f.UserAId, f.UserBId };
    }

    public async Task<bool> IsMemberAsync(Guid conversationId, Guid userId, CancellationToken ct = default)
    {
        return await db.Friendships
            .AnyAsync(x => x.Id == conversationId
                && (x.UserAId == userId || x.UserBId == userId), ct);
    }
}
