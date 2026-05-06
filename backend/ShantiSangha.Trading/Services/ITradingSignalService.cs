using ShantiSangha.Trading.Contracts;

namespace ShantiSangha.Trading.Services;

public interface ITradingSignalService
{
    /// <summary>Returns today's signals for the user's whole watchlist.</summary>
    Task<IReadOnlyList<TradingSignalDto>> GetTodayAsync(Guid userId, CancellationToken ct = default);

    /// <summary>Generates and persists a fresh signal for one ticker. Used by the daily job and on-demand refresh.</summary>
    Task<TradingSignalDto?> GenerateAsync(Guid userId, string ticker, DateOnly date, CancellationToken ct = default);
}
