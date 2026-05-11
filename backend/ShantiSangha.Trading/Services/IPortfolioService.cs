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
    /// Add a single position. Throws InvalidOperationException if the user
    /// already holds the ticker — callers should remove first to re-enter.
    /// </summary>
    Task<PortfolioPositionDto> AddAsync(
        Guid userId,
        SavePortfolioPosition position,
        CancellationToken ct = default);

    /// <summary>
    /// Remove a single position by ticker. Returns false if the user didn't
    /// hold the ticker.
    /// </summary>
    Task<bool> RemoveAsync(
        Guid userId,
        string ticker,
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

    /// <summary>
    /// Symbol search + side-data enrichment for the iOS search bar.
    /// Reuses the existing sector cache (no yfinance fallback — speed
    /// matters here) and scores from cached bars only (skips tickers with
    /// &lt; 100 cached bars). Scores are at the user's entry horizon.
    /// </summary>
    Task<IReadOnlyList<EnrichedSymbolMatchDto>> SearchEnrichedAsync(
        Guid userId,
        string query,
        int limit,
        CancellationToken ct = default);

    /// <summary>
    /// Watchlist enriched with the same sector + p_buy/p_sell shape as
    /// the search-enrichment path. Held tickers are excluded so the
    /// "Watching" surface only shows pure interest items (no double
    /// display with the holdings section).
    /// </summary>
    Task<IReadOnlyList<EnrichedSymbolMatchDto>> ListWatchlistEnrichedAsync(
        Guid userId,
        CancellationToken ct = default);
}
