using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public interface IStrategySettingsService
{
    /// <summary>
    /// Returns the user's strategy settings. If none exist, creates a row
    /// with the Mode D active-trader defaults and returns it.
    /// </summary>
    Task<UserStrategySettings> GetOrCreateAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Apply a partial update. Any null field in the request is left
    /// untouched. Validation enforces sane ranges (stop &gt; 0, &lt; 0.5,
    /// horizon ∈ {"1W","1M","1Y"}, etc.).
    /// </summary>
    Task<UserStrategySettings> UpdateAsync(
        Guid userId,
        UpdateStrategySettingsRequest request,
        CancellationToken ct = default);
}
