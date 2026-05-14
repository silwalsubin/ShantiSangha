using Microsoft.EntityFrameworkCore;
using ShantiSangha.Friends.Data;

namespace ShantiSangha.Friends.Services;

public class FriendMessageSuggestionService(FriendsDbContext db) : IFriendMessageSuggestionService
{
    public async Task<bool> DismissAsync(Guid userId, Guid messageId, CancellationToken ct = default)
    {
        var row = await db.MessageSuggestions
            .FirstOrDefaultAsync(s => s.FriendMessageId == messageId && s.UserId == userId, ct);
        if (row is null) return false;

        // Idempotent — re-dismissing a dismissed row is a no-op success.
        if (row.DismissedAt.HasValue) return true;

        row.DismissedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> AcceptAsync(Guid userId, Guid messageId, Guid reminderId, CancellationToken ct = default)
    {
        var row = await db.MessageSuggestions
            .FirstOrDefaultAsync(s => s.FriendMessageId == messageId && s.UserId == userId, ct);
        if (row is null) return false;

        row.CreatedReminderId = reminderId;
        await db.SaveChangesAsync(ct);
        return true;
    }
}
