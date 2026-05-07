using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public record MarketBar(DateOnly Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

public record QuoteSnapshot(string Ticker, decimal Price, decimal? PrevClose, decimal? DayHigh, decimal? DayLow);

public record TechnicalSignalContribution(string Name, double Value, double Contribution, double Weight);

public record TechnicalScore(string Ticker, decimal? Price, double Score, IReadOnlyList<TechnicalSignalContribution> Contributions);

public record ScoreInput(string Ticker, IReadOnlyList<MarketBar> Bars, decimal? Price);

public record SymbolMatch(string Symbol, string Description, string Type);

/// <summary>
/// `Date` is a passthrough string — daily bars use "yyyy-MM-dd", intraday
/// bars use full ISO timestamps. iOS handles both formats; the .NET layer
/// doesn't parse, so adding new resolutions doesn't require schema changes.
/// </summary>
public record ChartBar(string Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

public record ChartAggregates(
    decimal CurrentPrice,
    decimal? PreviousClose,
    decimal? WeekHigh52,
    decimal? WeekLow52,
    decimal AllTimeHigh,
    decimal AllTimeLow,
    DateOnly FirstDate,
    DateOnly LatestDate
);

public record ChartHistoryResult(string Ticker, string Period, IReadOnlyList<ChartBar> Bars, ChartAggregates? Aggregates);

/// <summary>
/// Wraps the Python wisecat service. The .NET side owns the durable bar cache;
/// this client only uses Python for (a) computing technical scores from bars
/// and (b) fetching missing bars / live quotes / symbol search from Finnhub.
/// </summary>
public interface IMarketDataClient
{
    /// <summary>Fetch bars from Finnhub on or after `fromDate`. Used for delta backfill of TickerDailyClose.</summary>
    Task<IReadOnlyList<MarketBar>> GetHistoryAsync(string ticker, DateOnly fromDate, CancellationToken ct = default);

    /// <summary>Live quote (15-min delayed on free Finnhub).</summary>
    Task<QuoteSnapshot?> GetQuoteAsync(string ticker, CancellationToken ct = default);

    /// <summary>Pure compute. Caller passes bars from local cache.</summary>
    Task<IReadOnlyList<TechnicalScore>> ScoreAsync(IReadOnlyList<ScoreInput> items, CancellationToken ct = default);

    /// <summary>Symbol search — used for watchlist add validation + iOS suggestions.</summary>
    Task<IReadOnlyList<SymbolMatch>> SearchSymbolsAsync(string query, int limit = 10, CancellationToken ct = default);

    /// <summary>Long-range chart data + 52w / all-time aggregates. yfinance-backed (free, unlimited).</summary>
    Task<ChartHistoryResult?> GetChartHistoryAsync(string ticker, string period, CancellationToken ct = default);
}
