using ShantiSangha.Identity.Contracts;

namespace ShantiSangha.Identity.Services;

public interface IUserSearchService
{
    /// <summary>
    /// Search the user directory by display name (fuzzy substring) and/or
    /// location (matches Country / State / City). Filters out the current
    /// user and any of their existing friends. At least one of `q` or
    /// `location` must be non-empty — the controller enforces this and
    /// returns 400; the service treats both-empty as a no-results page.
    /// </summary>
    /// <param name="currentUserId">The signed-in user. Excluded from results,
    /// and used to look up their friends so those are excluded too.</param>
    /// <param name="page">1-based.</param>
    /// <param name="pageSize">Clamped to [1, 50] inside the service.</param>
    Task<UserSearchPage> SearchAsync(
        Guid currentUserId,
        string? q,
        string? location,
        int page,
        int pageSize,
        CancellationToken ct = default);
}
