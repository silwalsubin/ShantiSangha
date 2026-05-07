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

        // Pull cached bars; if fewer than 200 (smallest indicator window), backfill.
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

        // Per-horizon technical scores (Lambda).
        var scores = await marketData.ScoreAsync(
            new[] { new ScoreInput(ticker, bars, price) }, ct);
        var techScore = scores.FirstOrDefault();
        var tech1W = techScore?.Horizon1W ?? new HorizonTechnicalScore(0.0, Array.Empty<TechnicalSignalContribution>());
        var tech1M = techScore?.Horizon1M ?? new HorizonTechnicalScore(0.0, Array.Empty<TechnicalSignalContribution>());
        var tech1Y = techScore?.Horizon1Y ?? new HorizonTechnicalScore(0.0, Array.Empty<TechnicalSignalContribution>());

        // Per-horizon astro composites.
        var astroResult = await astro.ComputeAsync(userId, ticker, DateTime.UtcNow, ct);

        // Per-horizon composites.
        var composite1W = ClampComposite(TechnicalWeight * tech1W.Score + AstroWeight * astroResult.Composite1W);
        var composite1M = ClampComposite(TechnicalWeight * tech1M.Score + AstroWeight * astroResult.Composite1M);
        var composite1Y = ClampComposite(TechnicalWeight * tech1Y.Score + AstroWeight * astroResult.Composite1Y);

        var action1W = ToAction(composite1W);
        var action1M = ToAction(composite1M);
        var action1Y = ToAction(composite1Y);

        var reasoning = new SignalReasoning(
            Technical1W: tech1W.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList(),
            Technical1M: tech1M.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList(),
            Technical1Y: tech1Y.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList(),
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

        existing.Action1W = action1W;
        existing.Action1M = action1M;
        existing.Action1Y = action1Y;
        existing.Conviction1W = Math.Abs(composite1W);
        existing.Conviction1M = Math.Abs(composite1M);
        existing.Conviction1Y = Math.Abs(composite1Y);
        existing.Technical1W = tech1W.Score;
        existing.Technical1M = tech1M.Score;
        existing.Technical1Y = tech1Y.Score;
        existing.Astro1W = astroResult.Composite1W;
        existing.Astro1M = astroResult.Composite1M;
        existing.Astro1Y = astroResult.Composite1Y;
        existing.Composite1W = composite1W;
        existing.Composite1M = composite1M;
        existing.Composite1Y = composite1Y;

        // Legacy single-horizon columns mirror the 1M values.
        existing.Action = action1M;
        existing.Conviction = Math.Abs(composite1M);
        existing.TechnicalScore = tech1M.Score;
        existing.AstroScore = astroResult.Composite1M;
        existing.CompositeScore = composite1M;

        existing.ReasoningJson = reasoningJson;
        existing.PriceAtSignal = price;
        existing.CreatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
        return ToDto(existing);
    }

    private static double ClampComposite(double composite) => Math.Clamp(composite, -1.0, 1.0);

    private static TradingAction ToAction(double composite) =>
        composite > BuyThreshold ? TradingAction.Buy
        : composite < SellThreshold ? TradingAction.Sell
        : TradingAction.Hold;

    private async Task BackfillAsync(string ticker, DateOnly fromDate, CancellationToken ct)
    {
        var bars = await marketData.GetHistoryAsync(ticker, fromDate, ct);
        if (bars.Count == 0) return;

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
        // Rows persisted before the per-horizon split have ReasoningJson with
        // a `Technical` field instead of `Technical1W/1M/1Y`, so those three
        // properties deserialize as null. Coalesce so the API never emits
        // null lists where iOS expects an array.
        var raw = JsonSerializer.Deserialize<SignalReasoning>(s.ReasoningJson);
        var reasoning = new SignalReasoning(
            Technical1W: raw?.Technical1W ?? Array.Empty<StrategyContributionDto>(),
            Technical1M: raw?.Technical1M ?? Array.Empty<StrategyContributionDto>(),
            Technical1Y: raw?.Technical1Y ?? Array.Empty<StrategyContributionDto>(),
            Astro:       raw?.Astro       ?? Array.Empty<AstroAngleScoreDto>()
        );

        var horizon1W = new HorizonReadDto(
            Action: s.Action1W.ToString(),
            Conviction: s.Conviction1W,
            TechnicalScore: s.Technical1W,
            AstroScore: s.Astro1W,
            CompositeScore: s.Composite1W,
            TechnicalSignals: reasoning.Technical1W
        );
        var horizon1M = new HorizonReadDto(
            Action: s.Action1M.ToString(),
            Conviction: s.Conviction1M,
            TechnicalScore: s.Technical1M,
            AstroScore: s.Astro1M,
            CompositeScore: s.Composite1M,
            TechnicalSignals: reasoning.Technical1M
        );
        var horizon1Y = new HorizonReadDto(
            Action: s.Action1Y.ToString(),
            Conviction: s.Conviction1Y,
            TechnicalScore: s.Technical1Y,
            AstroScore: s.Astro1Y,
            CompositeScore: s.Composite1Y,
            TechnicalSignals: reasoning.Technical1Y
        );

        return new TradingSignalDto(
            Ticker: s.Ticker,
            Date: s.Date,
            // Legacy top-level fields = 1M view.
            Action: horizon1M.Action,
            Conviction: horizon1M.Conviction,
            TechnicalScore: horizon1M.TechnicalScore,
            AstroScore: horizon1M.AstroScore,
            CompositeScore: horizon1M.CompositeScore,
            Price: s.PriceAtSignal,
            TechnicalSignals: horizon1M.TechnicalSignals,
            AstroAngles: reasoning.Astro,
            Horizon1W: horizon1W,
            Horizon1M: horizon1M,
            Horizon1Y: horizon1Y
        );
    }
}
