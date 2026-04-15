namespace ShantiSangha.Shared.Interfaces;

public interface IReflectionQueryService
{
    /// <summary>
    /// Returns the user's most recent daily reflection content if one exists
    /// within the past 2 days, otherwise null. No timezone parameter needed —
    /// "most recent" is robust to timezone drift.
    /// </summary>
    Task<string?> GetRecentReflectionAsync(Guid userId, CancellationToken ct = default);
}
