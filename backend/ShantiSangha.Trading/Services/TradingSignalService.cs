using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class TradingSignalService(
    TradingDbContext db,
    IMarketDataClient marketData,
    IAstroSignalService astro,
    ILogger<TradingSignalService> logger) : ITradingSignalService
{
    private const double TechnicalWeight = 0.6;
    private const double AstroWeight = 0.4;
    private const double BuyThreshold = 0.5;
    private const double SellThreshold = -0.5;

    public async Task<IReadOnlyList<TradingSignalDto>> GetTodayAsync(Guid userId, CancellationToken ct = default)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var rows = await db.TradingSignals
            .Where(s => s.UserId == userId && s.Date == today)
            .ToListAsync(ct);
        return rows.Select(ToDto).ToList();
    }

    public async Task<TradingSignalDto?> GenerateAsync(Guid userId, string ticker, DateOnly date, CancellationToken ct = default)
    {
        ticker = ticker.Trim().ToUpperInvariant();

        // Pull cached bars; if fewer than 200 (smallest indicator window), backfill from Finnhub.
        var cutoff = date.AddDays(-450); // 400 trading-day lookback + buffer
        var bars = await db.TickerDailyCloses
            .Where(b => b.Ticker == ticker && b.Date <= date && b.Date >= cutoff)
            .OrderBy(b => b.Date)
            .Select(b => new MarketBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume))
            .ToListAsync(ct);

        if (bars.Count < 200)
        {
            logger.LogInformation("Backfilling history for {Ticker} (have {Count} bars)", ticker, bars.Count);
            await BackfillAsync(ticker, date.AddDays(-450), ct);
            bars = await db.TickerDailyCloses
                .Where(b => b.Ticker == ticker && b.Date <= date && b.Date >= cutoff)
                .OrderBy(b => b.Date)
                .Select(b => new MarketBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume))
                .ToListAsync(ct);
        }

        // Quote (live; not cached).
        var quote = await marketData.GetQuoteAsync(ticker, ct);
        decimal? price = quote?.Price ?? (bars.Count > 0 ? bars[^1].Close : (decimal?)null);

        // Technical score (pure compute on Python; bars are sent in-line).
        var scores = await marketData.ScoreAsync(
            new[] { new ScoreInput(ticker, bars, price) }, ct);
        var techScore = scores.FirstOrDefault();
        var technical = techScore?.Score ?? 0.0;

        // Astro score.
        var astroResult = await astro.ComputeAsync(userId, ticker, DateTime.UtcNow, ct);

        var composite = TechnicalWeight * technical + AstroWeight * astroResult.CompositeScore;
        composite = Math.Clamp(composite, -1.0, 1.0);

        var action = composite > BuyThreshold ? TradingAction.Buy
                   : composite < SellThreshold ? TradingAction.Sell
                   : TradingAction.Hold;

        var reasoning = new SignalReasoning(
            Technical: techScore?.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution))
                .ToList() ?? [],
            Astro: astroResult.Angles
                .Select(a => new AstroAngleScoreDto(a.Name, a.Score, a.Highlights))
                .ToList()
        );
        var reasoningJson = JsonSerializer.Serialize(reasoning);

        // Upsert today's signal for this user/ticker.
        var existing = await db.TradingSignals
            .FirstOrDefaultAsync(s => s.UserId == userId && s.Ticker == ticker && s.Date == date, ct);

        if (existing is null)
        {
            existing = new TradingSignal
            {
                UserId = userId,
                Ticker = ticker,
                Date = date,
            };
            db.TradingSignals.Add(existing);
        }

        existing.Action = action;
        existing.Conviction = Math.Abs(composite);
        existing.TechnicalScore = technical;
        existing.AstroScore = astroResult.CompositeScore;
        existing.CompositeScore = composite;
        existing.ReasoningJson = reasoningJson;
        existing.PriceAtSignal = price;
        existing.CreatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
        return ToDto(existing);
    }

    private async Task BackfillAsync(string ticker, DateOnly fromDate, CancellationToken ct)
    {
        var bars = await marketData.GetHistoryAsync(ticker, fromDate, ct);
        if (bars.Count == 0) return;

        // Upsert: skip dates we already have.
        var existingDates = await db.TickerDailyCloses
            .Where(b => b.Ticker == ticker && b.Date >= fromDate)
            .Select(b => b.Date)
            .ToListAsync(ct);
        var existingSet = new HashSet<DateOnly>(existingDates);

        foreach (var bar in bars)
        {
            if (existingSet.Contains(bar.Date)) continue;
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
        }
        await db.SaveChangesAsync(ct);
    }

    private static TradingSignalDto ToDto(TradingSignal s)
    {
        var reasoning = JsonSerializer.Deserialize<SignalReasoning>(s.ReasoningJson)
                        ?? new SignalReasoning([], []);
        return new TradingSignalDto(
            Ticker: s.Ticker,
            Date: s.Date,
            Action: s.Action.ToString(),
            Conviction: s.Conviction,
            TechnicalScore: s.TechnicalScore,
            AstroScore: s.AstroScore,
            CompositeScore: s.CompositeScore,
            Price: s.PriceAtSignal,
            TechnicalSignals: reasoning.Technical,
            AstroAngles: reasoning.Astro
        );
    }
}
