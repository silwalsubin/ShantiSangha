namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Read-only window into the Friends module's friendship graph for other
/// modules. The Identity module uses this to filter user-search results so
/// existing friends don't show up — without coupling to the Friends DbContext
/// directly. Mirrors the pattern of `IProfileQueryService` (Identity → other
/// modules) and `IPracticeQueryService` (Goals → other modules).
/// </summary>
public interface IFriendsQueryService
{
    /// <summary>
    /// Returns the set of user IDs that are currently friends with
    /// <paramref name="userId"/>. The set is empty (not null) when the user
    /// has no friends. Cheap enough to call per-request — backed by a single
    /// indexed query against the `Friendships` table.
    /// </summary>
    Task<HashSet<Guid>> GetFriendUserIdsAsync(Guid userId, CancellationToken ct = default);
}
