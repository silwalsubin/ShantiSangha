using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;
using ShantiSangha.Trading.Services;

namespace ShantiSangha.Trading.Jobs;

/// <summary>
/// After RefreshMarketDataJob has populated the cache: for each user with a
/// non-empty watchlist, generate today's signals (technical) and dispatch
/// a push for any high-conviction call.
/// </summary>
public class GenerateDailyTradingSignalsJob(
    TradingDbContext db,
    ITradingSignalService signalService,
    INotificationService notifications,
    ILogger<GenerateDailyTradingSignalsJob> logger)
{
    private const double PushThreshold = 0.7;

    public async Task RunAsync()
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        var userTickers = await db.WatchlistItems
            .GroupBy(w => w.UserId)
            .Select(g => new { UserId = g.Key, Tickers = g.Select(w => w.Ticker).ToList() })
            .ToListAsync();

        var totalGenerated = 0;
        var totalPushes = 0;

        foreach (var entry in userTickers)
        {
            foreach (var ticker in entry.Tickers)
            {
                try
                {
                    var dto = await signalService.GenerateAsync(entry.UserId, ticker, today);
                    if (dto is null) continue;
                    totalGenerated++;

                    if (dto.Conviction >= PushThreshold && dto.Action != nameof(TradingAction.Hold))
                    {
                        await notifications.EnqueueAsync(
                            entry.UserId,
                            "trading_signal",
                            new
                            {
                                ticker = dto.Ticker,
                                action = dto.Action,
                                conviction = dto.Conviction,
                                price = dto.Price,
                                date = dto.Date,
                            });
                        totalPushes++;
                    }
                }
                catch (Exception e)
                {
                    logger.LogWarning(e, "signal generation failed for {UserId} {Ticker}", entry.UserId, ticker);
                }
            }
        }

        logger.LogInformation(
            "GenerateDailyTradingSignals: generated {Signals} signals, dispatched {Pushes} high-conviction notifications",
            totalGenerated, totalPushes);
    }
}
