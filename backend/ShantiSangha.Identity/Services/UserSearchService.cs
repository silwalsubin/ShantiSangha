using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Identity.Contracts;
using ShantiSangha.Identity.Data;
using ShantiSangha.Identity.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class UserSearchService(
    IdentityDbContext db,
    IFriendsQueryService friendsQuery,
    AvatarStorage avatarStorage,
    ILogger<UserSearchService> logger) : IUserSearchService
{
    private static readonly TimeSpan AvatarUrlLifetime = TimeSpan.FromHours(1);
    private const int MaxPageSize = 50;
    private const int DefaultPageSize = 20;

    public async Task<UserSearchPage> SearchAsync(
        Guid currentUserId,
        string? q,
        string? location,
        int page,
        int pageSize,
        CancellationToken ct = default)
    {
        var clampedPage = Math.Max(page, 1);
        var clampedPageSize = Math.Clamp(pageSize <= 0 ? DefaultPageSize : pageSize, 1, MaxPageSize);

        var trimmedQ = string.IsNullOrWhiteSpace(q) ? null : q.Trim();
        var trimmedLoc = string.IsNullOrWhiteSpace(location) ? null : location.Trim();

        // Both empty → empty page. Caller shouldn't hit this path because the
        // controller enforces "at least one filter", but be defensive.
        if (trimmedQ is null && trimmedLoc is null)
        {
            return new UserSearchPage(clampedPage, clampedPageSize, 0, false, new List<UserSearchResult>());
        }

        var friendIds = await friendsQuery.GetFriendUserIdsAsync(currentUserId, ct);

        // Build the filtered query. Join Profile to User (Profile.UserId is
        // the FK; we need User.Id later for excluding the current user and
        // any deleted/inactive accounts). Use AsNoTracking for read-only
        // throughput.
        var query = db.Profiles
            .AsNoTracking()
            .Where(p => p.UserId != currentUserId)
            .Where(p => p.DisplayName != null && p.DisplayName != "");

        if (friendIds.Count > 0)
        {
            query = query.Where(p => !friendIds.Contains(p.UserId));
        }

        if (trimmedQ is not null)
        {
            // Postgres ILIKE — case-insensitive substring. With the GIN
            // trigram index added in 20260425120000_AddUserSearchIndexes,
            // Postgres can serve this from the index without a sequential
            // scan at any reasonable user-table size.
            var like = $"%{trimmedQ}%";
            query = query.Where(p => EF.Functions.ILike(p.DisplayName!, like));
        }

        if (trimmedLoc is not null)
        {
            // Location matches Country OR State OR City. We use ILIKE on all
            // three (case-insensitive substring) — typed string is freeform,
            // could be either a country, state, or city or a fragment of any.
            var locLike = $"%{trimmedLoc}%";
            query = query.Where(p =>
                (p.Country != null && EF.Functions.ILike(p.Country, locLike)) ||
                (p.State != null && EF.Functions.ILike(p.State, locLike)) ||
                (p.City != null && EF.Functions.ILike(p.City, locLike)));
        }

        var totalCount = await query.CountAsync(ct);

        var rows = await query
            .OrderBy(p => p.DisplayName)
            .Skip((clampedPage - 1) * clampedPageSize)
            .Take(clampedPageSize)
            .Select(p => new
            {
                p.UserId,
                p.DisplayName,
                p.Country,
                p.State,
                p.City,
                p.AvatarKey
            })
            .ToListAsync(ct);

        var results = new List<UserSearchResult>(rows.Count);
        foreach (var row in rows)
        {
            string? avatarUrl = null;
            if (!string.IsNullOrEmpty(row.AvatarKey))
            {
                try
                {
                    avatarUrl = await avatarStorage.GetPresignedDownloadUrlAsync(row.AvatarKey, AvatarUrlLifetime);
                }
                catch (Exception ex)
                {
                    // Per-row presign failure is non-fatal — let the row
                    // through with null URL and the iOS layer falls back to
                    // initials.
                    logger.LogWarning(ex, "Failed to presign avatar URL for user {UserId}", row.UserId);
                }
            }

            results.Add(new UserSearchResult(
                row.UserId,
                row.DisplayName ?? string.Empty,
                row.Country,
                row.State,
                row.City,
                row.AvatarKey,
                avatarUrl));
        }

        var hasMore = (clampedPage * clampedPageSize) < totalCount;
        return new UserSearchPage(clampedPage, clampedPageSize, totalCount, hasMore, results);
    }
}
