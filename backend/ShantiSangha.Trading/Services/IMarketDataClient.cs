using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public record MarketBar(DateOnly Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

public record QuoteSnapshot(string Ticker, decimal Price, decimal? PrevClose, decimal? DayHigh, decimal? DayLow);

public record TechnicalSignalContribution(string Name, double Value, double Contribution);

public record TechnicalScore(string Ticker, decimal? Price, double Score, IReadOnlyList<TechnicalSignalContribution> Contributions);

public record ScoreInput(string Ticker, IReadOnlyList<MarketBar> Bars, decimal? Price);

/// <summary>
/// Wraps the Python wisecat service. The .NET side owns the durable bar cache;
/// this client only uses Python for (a) computing technical scores from bars
/// and (b) fetching missing bars / live quotes from Finnhub.
/// </summary>
public interface IMarketDataClient
{
    /// <summary>Fetch bars from Finnhub on or after `fromDate`. Used for delta backfill of TickerDailyClose.</summary>
    Task<IReadOnlyList<MarketBar>> GetHistoryAsync(string ticker, DateOnly fromDate, CancellationToken ct = default);

    /// <summary>Live quote (15-min delayed on free Finnhub).</summary>
    Task<QuoteSnapshot?> GetQuoteAsync(string ticker, CancellationToken ct = default);

    /// <summary>Pure compute. Caller passes bars from local cache.</summary>
    Task<IReadOnlyList<TechnicalScore>> ScoreAsync(IReadOnlyList<ScoreInput> items, CancellationToken ct = default);
}
