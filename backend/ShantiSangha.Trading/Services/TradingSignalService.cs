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
    ILogger<TradingSignalService> logger) : ITradingSignalService
{
    // Probability-based verdict derivation. The legacy ±0.5 threshold on
    // (pBuy − pSell) essentially never fired — it required the model to be
    // near-certain. These thresholds operate on the raw class probabilities
    // and err toward Hold when the model is uncertain.
    //
    // Rule: act only when the chosen class clears an absolute floor AND
    // beats the highest competing class by a margin. With a 3-class softmax
    // the random baseline is 0.33 per class, so 0.40 is "noticeably above
    // chance" and 0.10 margin filters out near-ties.
    //
    // Per-horizon tuning (tighter floor for 1W, vol-regime calibration) is
    // a deliberate follow-up — see the WiseCat audit Phase 2.
    private const double ActionProbabilityFloor = 0.40;
    private const double ActionMarginOverNextClass = 0.10;

    public async Task<IReadOnlyList<TradingSignalDto>> GetTodayAsync(Guid userId, CancellationToken ct = default)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // Filter to currently-watchlisted tickers — RemoveAsync deletes the
        // WatchlistItem but leaves the TradingSignal row, so without this
        // filter the home card and any consumer of GetTodayAsync would
        // count signals from tickers the user has already removed.
        var watchedTickers = await db.WatchlistItems
            .Where(w => w.UserId == userId)
            .Select(w => w.Ticker)
            .ToListAsync(ct);

        var rows = await db.TradingSignals
            .Where(s => s.UserId == userId
                && s.Date == today
                && watchedTickers.Contains(s.Ticker))
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
        var tech1W = techScore?.Horizon1W ?? new HorizonTechnicalScore(0.0, 0.0, 1.0, 0.0, 0.0, Array.Empty<TechnicalSignalContribution>());
        var tech1M = techScore?.Horizon1M ?? new HorizonTechnicalScore(0.0, 0.0, 1.0, 0.0, 0.0, Array.Empty<TechnicalSignalContribution>());
        var tech1Y = techScore?.Horizon1Y ?? new HorizonTechnicalScore(0.0, 0.0, 1.0, 0.0, 0.0, Array.Empty<TechnicalSignalContribution>());

        // Composite is purely technical now.
        var composite1W = ClampComposite(tech1W.Score);
        var composite1M = ClampComposite(tech1M.Score);
        var composite1Y = ClampComposite(tech1Y.Score);

        var (action1W, conviction1W) = DeriveVerdict(tech1W.PBuy, tech1W.PHold, tech1W.PSell);
        var (action1M, conviction1M) = DeriveVerdict(tech1M.PBuy, tech1M.PHold, tech1M.PSell);
        var (action1Y, conviction1Y) = DeriveVerdict(tech1Y.PBuy, tech1Y.PHold, tech1Y.PSell);

        var reasoning = new SignalReasoning(
            Technical1W: tech1W.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList(),
            Technical1M: tech1M.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList(),
            Technical1Y: tech1Y.Contributions
                .Select(c => new StrategyContributionDto(c.Name, c.Value, c.Contribution, c.Weight))
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
        existing.Conviction1W = conviction1W;
        existing.Conviction1M = conviction1M;
        existing.Conviction1Y = conviction1Y;
        existing.Technical1W = tech1W.Score;
        existing.Technical1M = tech1M.Score;
        existing.Technical1Y = tech1Y.Score;
        existing.Composite1W = composite1W;
        existing.Composite1M = composite1M;
        existing.Composite1Y = composite1Y;

        // GBM-classifier probabilities. Until the Python Lambda is upgraded
        // these come back as the neutral default (pHold=1, others 0) so the
        // verdict reads as "fully Hold" and rows are valid for downstream
        // consumers without special-casing legacy.
        existing.PBuy1W = tech1W.PBuy;
        existing.PHold1W = tech1W.PHold;
        existing.PSell1W = tech1W.PSell;
        existing.ExpectedReturn1W = tech1W.ExpectedReturn;
        existing.PBuy1M = tech1M.PBuy;
        existing.PHold1M = tech1M.PHold;
        existing.PSell1M = tech1M.PSell;
        existing.ExpectedReturn1M = tech1M.ExpectedReturn;
        existing.PBuy1Y = tech1Y.PBuy;
        existing.PHold1Y = tech1Y.PHold;
        existing.PSell1Y = tech1Y.PSell;
        existing.ExpectedReturn1Y = tech1Y.ExpectedReturn;

        existing.ReasoningJson = reasoningJson;
        existing.PriceAtSignal = price;
        existing.LastBarDate = bars.Count > 0 ? bars[^1].Date : date;
        existing.CreatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
        return ToDto(existing);
    }

    private static double ClampComposite(double composite) => Math.Clamp(composite, -1.0, 1.0);

    internal static (TradingAction action, double conviction) DeriveVerdict(
        double pBuy, double pHold, double pSell)
    {
        // All-zero sentinel from the Python neutral fallback (GBM artifact
        // missing or scoring failed). Distinct from a real "fully Hold"
        // prediction whose triple sums to ~1.0.
        if (pBuy + pHold + pSell <= 0.001)
        {
            return (TradingAction.Hold, 0.0);
        }

        var competingForBuy = Math.Max(pHold, pSell);
        if (pBuy >= ActionProbabilityFloor && pBuy >= competingForBuy + ActionMarginOverNextClass)
        {
            return (TradingAction.Buy, pBuy);
        }

        var competingForSell = Math.Max(pHold, pBuy);
        if (pSell >= ActionProbabilityFloor && pSell >= competingForSell + ActionMarginOverNextClass)
        {
            return (TradingAction.Sell, pSell);
        }

        return (TradingAction.Hold, pHold);
    }

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
            Technical1Y: raw?.Technical1Y ?? Array.Empty<StrategyContributionDto>()
        );

        var horizon1W = new HorizonReadDto(
            Action: s.Action1W.ToString(),
            Conviction: s.Conviction1W,
            TechnicalScore: s.Technical1W,
            CompositeScore: s.Composite1W,
            PBuy: s.PBuy1W,
            PHold: s.PHold1W,
            PSell: s.PSell1W,
            ExpectedReturn: s.ExpectedReturn1W,
            TechnicalSignals: reasoning.Technical1W
        );
        var horizon1M = new HorizonReadDto(
            Action: s.Action1M.ToString(),
            Conviction: s.Conviction1M,
            TechnicalScore: s.Technical1M,
            CompositeScore: s.Composite1M,
            PBuy: s.PBuy1M,
            PHold: s.PHold1M,
            PSell: s.PSell1M,
            ExpectedReturn: s.ExpectedReturn1M,
            TechnicalSignals: reasoning.Technical1M
        );
        var horizon1Y = new HorizonReadDto(
            Action: s.Action1Y.ToString(),
            Conviction: s.Conviction1Y,
            TechnicalScore: s.Technical1Y,
            CompositeScore: s.Composite1Y,
            PBuy: s.PBuy1Y,
            PHold: s.PHold1Y,
            PSell: s.PSell1Y,
            ExpectedReturn: s.ExpectedReturn1Y,
            TechnicalSignals: reasoning.Technical1Y
        );

        return new TradingSignalDto(
            Ticker: s.Ticker,
            Date: s.Date,
            // LastBarDate may be the migration default (= s.Date) for rows
            // upserted before tomorrow's first batch — that's fine; one
            // refresh later it converges to the real last-bar date.
            LastBarDate: s.LastBarDate,
            // Legacy top-level fields = 1M view.
            Action: horizon1M.Action,
            Conviction: horizon1M.Conviction,
            TechnicalScore: horizon1M.TechnicalScore,
            CompositeScore: horizon1M.CompositeScore,
            Price: s.PriceAtSignal,
            TechnicalSignals: horizon1M.TechnicalSignals,
            Horizon1W: horizon1W,
            Horizon1M: horizon1M,
            Horizon1Y: horizon1Y
        );
    }
}
