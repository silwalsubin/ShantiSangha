using ShantiSangha.Trading.Contracts;

namespace ShantiSangha.Trading.Services;

public interface IPortfolioService
{
    Task<IReadOnlyList<PortfolioPositionDto>> ListAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Replace the user's portfolio with the provided positions (full overwrite —
    /// any prior positions not in the list are removed). Cash balance is not
    /// persisted; iOS passes it through with each plan request.
    /// </summary>
    Task<IReadOnlyList<PortfolioPositionDto>> ReplaceAsync(
        Guid userId,
        IReadOnlyList<SavePortfolioPosition> positions,
        CancellationToken ct = default);

    /// <summary>
    /// Score the user's current portfolio against the 10 ratified rules and
    /// produce an action plan. `cashBalance` is treated as un-invested cash
    /// for percent-of-portfolio math but not persisted.
    /// </summary>
    Task<PortfolioPlanDto> GeneratePlanAsync(
        Guid userId,
        decimal? cashBalance,
        CancellationToken ct = default);
}
