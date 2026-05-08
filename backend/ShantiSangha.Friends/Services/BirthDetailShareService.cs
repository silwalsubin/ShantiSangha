using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

/// <summary>
/// Implements <see cref="IBirthDetailShareService"/>. The interface lives in
/// Shared/Interfaces so other modules (Jyotish chart reading, future chat
/// surfaces) can gate on the share without referencing Friends directly.
/// </summary>

public class BirthDetailShareService(
    FriendsDbContext db,
    IProfileQueryService profileQuery,
    IPushNotificationService push,
    IPairChartReadingService pairReadings,
    ILogger<BirthDetailShareService> logger) : IBirthDetailShareService
{
    public async Task<bool> GrantAsync(Guid grantorUserId, Guid granteeUserId, CancellationToken ct = default)
    {
        if (grantorUserId == granteeUserId)
            throw new InvalidOperationException("cannot share birth details with yourself");

        // Friendship gate: shares only flow between actual friends. Without
        // this, the toggle could be used to leak chart data to anyone whose
        // user ID is known.
        if (!await AreFriendsAsync(grantorUserId, granteeUserId, ct))
            throw new InvalidOperationException("not friends");

        var existing = await db.BirthDetailShares.AsNoTracking().FirstOrDefaultAsync(
            s => s.GrantorUserId == grantorUserId && s.GranteeUserId == granteeUserId, ct);

        if (existing is not null) return false;

        db.BirthDetailShares.Add(new BirthDetailShare
        {
            Id = Guid.NewGuid(),
            GrantorUserId = grantorUserId,
            GranteeUserId = granteeUserId,
            GrantedAt = DateTime.UtcNow,
        });
        await db.SaveChangesAsync(ct);

        // Quiet notification — affirmative, not an "invite" demanding action.
        try
        {
            var grantorName = await profileQuery.GetDisplayNameAsync(grantorUserId, ct) ?? "A friend";
            await push.SendAlertPushAsync(granteeUserId,
                title: "Birth chart shared",
                body: $"{grantorName} shared their birth chart with you.",
                data: new Dictionary<string, string>
                {
                    ["type"] = "birth_details_shared",
                    ["grantorUserId"] = grantorUserId.ToString(),
                }, ct: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex,
                "Failed to send birth_details_shared push from {Grantor} to {Grantee}",
                grantorUserId, granteeUserId);
        }

        return true;
    }

    public async Task<bool> RevokeAsync(Guid grantorUserId, Guid granteeUserId, CancellationToken ct = default)
    {
        var deleted = await db.BirthDetailShares
            .Where(s => s.GrantorUserId == grantorUserId && s.GranteeUserId == granteeUserId)
            .ExecuteDeleteAsync(ct);

        if (deleted > 0)
        {
            // Honor the consent withdrawal: the grantee's reading and chat
            // about this person become inaccessible immediately. Wrapped so a
            // downstream failure doesn't roll back the revoke itself — the
            // share row is the source of truth, the pair reading is cache.
            try
            {
                await pairReadings.InvalidateAsync(granteeUserId, grantorUserId, ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Pair reading invalidation failed after revoke grantor={Grantor} grantee={Grantee} — share is gone but reading row may persist briefly.",
                    grantorUserId, granteeUserId);
            }
        }

        return deleted > 0;
    }

    public Task<bool> HasAccessAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default)
        => db.BirthDetailShares.AnyAsync(
            s => s.GrantorUserId == subjectUserId && s.GranteeUserId == viewerUserId, ct);

    public async Task<IReadOnlyList<Guid>> ListGrantedToAsync(Guid grantorUserId, CancellationToken ct = default)
        => await db.BirthDetailShares
            .Where(s => s.GrantorUserId == grantorUserId)
            .Select(s => s.GranteeUserId)
            .ToListAsync(ct);

    public async Task<IReadOnlyList<Guid>> ListReceivedFromAsync(Guid granteeUserId, CancellationToken ct = default)
        => await db.BirthDetailShares
            .Where(s => s.GranteeUserId == granteeUserId)
            .Select(s => s.GrantorUserId)
            .ToListAsync(ct);

    private async Task<bool> AreFriendsAsync(Guid userA, Guid userB, CancellationToken ct)
    {
        // Friendships normalize so smaller GUID is UserAId. Mirror the existing
        // check pattern from FriendsService.ExistsFriendshipAsync.
        var (a, b) = userA.CompareTo(userB) < 0 ? (userA, userB) : (userB, userA);
        return await db.Friendships.AnyAsync(f => f.UserAId == a && f.UserBId == b, ct);
    }
}
