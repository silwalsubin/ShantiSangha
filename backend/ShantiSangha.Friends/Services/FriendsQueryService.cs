using Microsoft.EntityFrameworkCore;
using ShantiSangha.Friends.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class FriendsQueryService(FriendsDbContext db) : IFriendsQueryService
{
    public async Task<HashSet<Guid>> GetFriendUserIdsAsync(Guid userId, CancellationToken ct = default)
    {
        // Friendship rows store the canonical pair as (UserAId < UserBId).
        // For each row containing `userId`, the OPPOSITE id is the friend.
        var pairs = await db.Friendships
            .Where(f => f.UserAId == userId || f.UserBId == userId)
            .Select(f => f.UserAId == userId ? f.UserBId : f.UserAId)
            .ToListAsync(ct);

        return pairs.ToHashSet();
    }
}
