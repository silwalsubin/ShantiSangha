using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;
using ShantiSangha.Trading.Services;

namespace ShantiSangha.Trading.Jobs;

/// <summary>
/// Once per trading day after US market close: for each unique ticker across
/// all users' watchlists, fetch only the missing bars from Finnhub (delta) and
/// store them in TickerDailyClose. Keeps Finnhub calls O(unique tickers).
/// </summary>
public class RefreshMarketDataJob(
    TradingDbContext db,
    IMarketDataClient marketData,
    ILogger<RefreshMarketDataJob> logger)
{
    private const int InitialBackfillDays = 400;

    public async Task RunAsync()
    {
        var tickers = await db.WatchlistItems
            .Select(w => w.Ticker)
            .Distinct()
            .ToListAsync();

        if (tickers.Count == 0)
        {
            logger.LogInformation("RefreshMarketData: no tickers to refresh");
            return;
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var inserted = 0;

        foreach (var ticker in tickers)
        {
            try
            {
                var lastCachedDate = await db.TickerDailyCloses
                    .Where(b => b.Ticker == ticker)
                    .Select(b => (DateOnly?)b.Date)
                    .OrderByDescending(d => d)
                    .FirstOrDefaultAsync();

                var fromDate = lastCachedDate.HasValue
                    ? lastCachedDate.Value.AddDays(1)
                    : today.AddDays(-InitialBackfillDays);

                if (fromDate > today)
                {
                    continue; // up to date
                }

                var bars = await marketData.GetHistoryAsync(ticker, fromDate);
                if (bars.Count == 0) continue;

                foreach (var bar in bars)
                {
                    if (bar.Date < fromDate) continue;
                    db.TickerDailyCloses.Add(new TickerDailyClose
                    {
                        Ticker = ticker,
                        Date = bar.Date,
                        Open = bar.Open,
                        High = bar.High,
                        Low = bar.Low,
                        Close = bar.Close,
                        Volume = bar.Volume,
                    });
                    inserted++;
                }
                await db.SaveChangesAsync();
            }
            catch (Exception e)
            {
                logger.LogWarning(e, "RefreshMarketData failed for {Ticker}", ticker);
            }
        }

        logger.LogInformation("RefreshMarketData: inserted {Inserted} new bars across {Tickers} tickers", inserted, tickers.Count);
    }
}
