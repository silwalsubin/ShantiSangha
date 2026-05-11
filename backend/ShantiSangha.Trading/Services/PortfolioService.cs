using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class PortfolioService(
    TradingDbContext db,
    IMarketDataClient marketData,
    IStrategySettingsService strategySettings,
    ILogger<PortfolioService> logger) : IPortfolioService
{
    // ---------- Defaults — overridden per-user via UserStrategySettings --
    // (All thresholds now come from UserStrategySettings; constants kept
    // only as fallback for older callers.)

    // Hardcoded sector overrides for common large-caps. Falls back to "Unknown"
    // for anything not listed — the iOS side surfaces those so user can
    // manually classify or accept the warning.
    private static readonly Dictionary<string, string> SectorOverrides = new(StringComparer.OrdinalIgnoreCase)
    {
        // Information Technology
        ["AAPL"] = "Information Technology",  ["MSFT"] = "Information Technology",
        ["NVDA"] = "Information Technology",  ["AMD"] = "Information Technology",
        ["INTC"] = "Information Technology",  ["AVGO"] = "Information Technology",
        ["CRM"] = "Information Technology",   ["ORCL"] = "Information Technology",
        ["ADBE"] = "Information Technology",  ["CSCO"] = "Information Technology",
        ["ACN"] = "Information Technology",   ["IBM"] = "Information Technology",
        ["QCOM"] = "Information Technology",  ["TXN"] = "Information Technology",
        ["NOW"] = "Information Technology",   ["PANW"] = "Information Technology",
        ["PLTR"] = "Information Technology",  ["SMCI"] = "Information Technology",
        // Health Care
        ["JNJ"] = "Health Care",  ["UNH"] = "Health Care",  ["PFE"] = "Health Care",
        ["LLY"] = "Health Care",  ["ABBV"] = "Health Care", ["MRK"] = "Health Care",
        ["TMO"] = "Health Care",  ["ABT"] = "Health Care",  ["DHR"] = "Health Care",
        ["BMY"] = "Health Care",  ["AMGN"] = "Health Care", ["CVS"] = "Health Care",
        ["ISRG"] = "Health Care",
        // Financials
        ["JPM"] = "Financials", ["BAC"] = "Financials", ["WFC"] = "Financials",
        ["GS"] = "Financials",  ["MS"] = "Financials",  ["C"] = "Financials",
        ["BLK"] = "Financials", ["BRK-A"] = "Financials", ["BRK-B"] = "Financials",
        ["BRK.A"] = "Financials", ["BRK.B"] = "Financials",
        ["V"] = "Financials",   ["MA"] = "Financials",  ["AXP"] = "Financials",
        ["SCHW"] = "Financials", ["COF"] = "Financials", ["USB"] = "Financials",
        // Consumer Discretionary
        ["HD"] = "Consumer Discretionary",   ["AMZN"] = "Consumer Discretionary",
        ["TSLA"] = "Consumer Discretionary", ["NKE"] = "Consumer Discretionary",
        ["MCD"] = "Consumer Discretionary",  ["SBUX"] = "Consumer Discretionary",
        ["LOW"] = "Consumer Discretionary",  ["BKNG"] = "Consumer Discretionary",
        ["ORLY"] = "Consumer Discretionary", ["TJX"] = "Consumer Discretionary",
        ["F"] = "Consumer Discretionary",    ["GM"] = "Consumer Discretionary",
        // Consumer Staples
        ["PG"] = "Consumer Staples",   ["KO"] = "Consumer Staples",
        ["PEP"] = "Consumer Staples",  ["WMT"] = "Consumer Staples",
        ["COST"] = "Consumer Staples", ["MO"] = "Consumer Staples",
        ["PM"] = "Consumer Staples",   ["CL"] = "Consumer Staples",
        ["MDLZ"] = "Consumer Staples", ["TGT"] = "Consumer Staples",
        // Communication Services
        ["VZ"] = "Communication Services",   ["T"] = "Communication Services",
        ["GOOGL"] = "Communication Services", ["GOOG"] = "Communication Services",
        ["META"] = "Communication Services", ["DIS"] = "Communication Services",
        ["NFLX"] = "Communication Services", ["CMCSA"] = "Communication Services",
        ["TMUS"] = "Communication Services",
        // Industrials
        ["CAT"] = "Industrials", ["BA"] = "Industrials", ["GE"] = "Industrials",
        ["HON"] = "Industrials", ["UPS"] = "Industrials", ["RTX"] = "Industrials",
        ["LMT"] = "Industrials", ["MMM"] = "Industrials", ["DE"] = "Industrials",
        ["UNP"] = "Industrials", ["FDX"] = "Industrials", ["NOC"] = "Industrials",
        // Energy
        ["XOM"] = "Energy", ["CVX"] = "Energy", ["COP"] = "Energy",
        ["EOG"] = "Energy", ["SLB"] = "Energy", ["OXY"] = "Energy",
        ["MPC"] = "Energy", ["PSX"] = "Energy",
        // Utilities
        ["NEE"] = "Utilities", ["DUK"] = "Utilities", ["SO"] = "Utilities",
        ["AEP"] = "Utilities", ["D"] = "Utilities",   ["EXC"] = "Utilities",
        // Materials
        ["APD"] = "Materials", ["LIN"] = "Materials", ["SHW"] = "Materials",
        ["ECL"] = "Materials", ["NEM"] = "Materials", ["FCX"] = "Materials",
        ["DD"] = "Materials",
        // Real Estate
        ["PLD"] = "Real Estate", ["AMT"] = "Real Estate", ["EQIX"] = "Real Estate",
        ["CCI"] = "Real Estate", ["O"] = "Real Estate",   ["SPG"] = "Real Estate",
    };

    // The 10-sector mega-cap basket — sector → preferred ticker.
    private static readonly Dictionary<string, string> SectorBasket = new()
    {
        ["Information Technology"] = "AAPL",
        ["Health Care"]            = "JNJ",
        ["Financials"]             = "JPM",
        ["Consumer Discretionary"] = "HD",
        ["Consumer Staples"]       = "PG",
        ["Communication Services"] = "VZ",
        ["Industrials"]            = "CAT",
        ["Energy"]                 = "XOM",
        ["Utilities"]              = "NEE",
        ["Materials"]              = "APD",
    };

    // ---------- CRUD --------------------------------------------------------

    public async Task<IReadOnlyList<PortfolioPositionDto>> ListAsync(Guid userId, CancellationToken ct = default)
    {
        return await db.UserPortfolioPositions
            .Where(p => p.UserId == userId)
            .OrderBy(p => p.Ticker)
            .Select(p => new PortfolioPositionDto(p.Ticker, p.Shares, p.CostBasis, p.UpdatedAt))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<PortfolioPositionDto>> ReplaceAsync(
        Guid userId,
        IReadOnlyList<SavePortfolioPosition> positions,
        CancellationToken ct = default)
    {
        // Validate first — reject the whole save on any bad row.
        var clean = new List<(string Ticker, decimal Shares, decimal CostBasis)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in positions)
        {
            var ticker = (p.Ticker ?? string.Empty).Trim().ToUpperInvariant();
            if (string.IsNullOrEmpty(ticker) || ticker.Length > 16)
                throw new InvalidOperationException($"ticker must be 1-16 characters: '{p.Ticker}'");
            if (p.Shares <= 0)
                throw new InvalidOperationException($"shares must be > 0 for {ticker}");
            if (p.CostBasis <= 0)
                throw new InvalidOperationException($"costBasis must be > 0 for {ticker}");
            if (!seen.Add(ticker))
                throw new InvalidOperationException($"duplicate ticker in request: {ticker}");
            clean.Add((ticker, p.Shares, p.CostBasis));
        }

        var existing = await db.UserPortfolioPositions
            .Where(p => p.UserId == userId)
            .ToListAsync(ct);
        db.UserPortfolioPositions.RemoveRange(existing);

        var now = DateTime.UtcNow;
        foreach (var (ticker, shares, costBasis) in clean)
        {
            db.UserPortfolioPositions.Add(new UserPortfolioPosition
            {
                UserId = userId,
                Ticker = ticker,
                Shares = shares,
                CostBasis = costBasis,
                CreatedAt = now,
                UpdatedAt = now,
            });
        }

        // Mirror held tickers into the watchlist so the daily-signal cron
        // keeps generating reads for them — the Stocks UI no longer shows
        // the watchlist directly, but the Home card and TradingSignal
        // pipeline still depend on it.
        var heldTickers = clean.Select(c => c.Ticker).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var alreadyWatched = await db.WatchlistItems
            .Where(w => w.UserId == userId && heldTickers.Contains(w.Ticker))
            .Select(w => w.Ticker)
            .ToListAsync(ct);
        var alreadyWatchedSet = new HashSet<string>(alreadyWatched, StringComparer.OrdinalIgnoreCase);
        foreach (var ticker in heldTickers)
        {
            if (alreadyWatchedSet.Contains(ticker)) continue;
            db.WatchlistItems.Add(new WatchlistItem
            {
                UserId = userId,
                Ticker = ticker,
                AddedAt = now,
            });
        }

        await db.SaveChangesAsync(ct);
        return await ListAsync(userId, ct);
    }

    public async Task<PortfolioPositionDto> AddAsync(
        Guid userId,
        SavePortfolioPosition position,
        CancellationToken ct = default)
    {
        var ticker = (position.Ticker ?? string.Empty).Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(ticker) || ticker.Length > 16)
            throw new InvalidOperationException($"ticker must be 1-16 characters: '{position.Ticker}'");
        if (position.Shares <= 0)
            throw new InvalidOperationException($"shares must be > 0 for {ticker}");
        if (position.CostBasis <= 0)
            throw new InvalidOperationException($"costBasis must be > 0 for {ticker}");

        var existing = await db.UserPortfolioPositions
            .FirstOrDefaultAsync(p => p.UserId == userId && p.Ticker == ticker, ct);
        if (existing is not null)
            throw new InvalidOperationException(
                $"You already hold {ticker}. Remove the existing position first to re-enter.");

        var now = DateTime.UtcNow;
        var row = new UserPortfolioPosition
        {
            UserId = userId,
            Ticker = ticker,
            Shares = position.Shares,
            CostBasis = position.CostBasis,
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.UserPortfolioPositions.Add(row);

        // Mirror into watchlist so the daily-signal cron picks it up.
        var alreadyWatched = await db.WatchlistItems
            .AnyAsync(w => w.UserId == userId && w.Ticker == ticker, ct);
        if (!alreadyWatched)
        {
            db.WatchlistItems.Add(new WatchlistItem
            {
                UserId = userId,
                Ticker = ticker,
                AddedAt = now,
            });
        }

        await db.SaveChangesAsync(ct);
        return new PortfolioPositionDto(row.Ticker, row.Shares, row.CostBasis, row.UpdatedAt);
    }

    public async Task<bool> RemoveAsync(
        Guid userId,
        string ticker,
        CancellationToken ct = default)
    {
        ticker = (ticker ?? string.Empty).Trim().ToUpperInvariant();
        var row = await db.UserPortfolioPositions
            .FirstOrDefaultAsync(p => p.UserId == userId && p.Ticker == ticker, ct);
        if (row is null) return false;

        // Rule 4 — if the position was removed at or below the user's
        // stop-loss threshold, log a stop-out so the plan generator can
        // block re-entry inside the cooldown window. Auto-detected from
        // the latest cached close; not perfect, but explicit enough.
        try
        {
            var settings = await strategySettings.GetOrCreateAsync(userId, ct);
            var stopLossPct = settings.StopLossPct;
            var latestClose = await db.TickerDailyCloses
                .Where(b => b.Ticker == ticker)
                .OrderByDescending(b => b.Date)
                .Select(b => b.Close)
                .FirstOrDefaultAsync(ct);
            if (latestClose > 0 && row.CostBasis > 0)
            {
                var lossPct = (latestClose / row.CostBasis) - 1m;
                if (lossPct <= -stopLossPct)
                {
                    db.StopOutLedgers.Add(new StopOutLedger
                    {
                        UserId = userId,
                        Ticker = ticker,
                        StoppedAt = DateTime.UtcNow,
                        ExitPrice = latestClose,
                        CostBasis = row.CostBasis,
                        LossPct = Math.Round(lossPct, 4),
                    });
                }
            }
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "Stop-out detection failed for {Ticker}; remove will still proceed", ticker);
        }

        db.UserPortfolioPositions.Remove(row);
        await db.SaveChangesAsync(ct);
        return true;
    }

    // ---------- Plan generation --------------------------------------------

    public async Task<PortfolioPlanDto> GeneratePlanAsync(
        Guid userId,
        decimal? cashBalance,
        CancellationToken ct = default)
    {
        // Pull the user's tunable rule constants. First call seeds defaults
        // (Mode D active-trader profile: -7% stop, +10% TP, 1W p_buy ≥ 0.60).
        var settings = await strategySettings.GetOrCreateAsync(userId, ct);
        var stopLossPct = (double)settings.StopLossPct;
        var takeProfitPct = (double)settings.TakeProfitPct;
        var entryThresholdPBuy = (double)settings.EntryThresholdPBuy;
        var positionCapPct = (double)settings.PositionCapPct;
        var minSectors = settings.MinSectors;
        var horizon = settings.EntryHorizon;
        var sellSignalPSell = (double)settings.SellSignalPSell;
        var cooldownDays = settings.CooldownDays;

        // Rule 4 — pull recent stop-outs so we can block re-entry. We only
        // need the most-recent stop per ticker; oldest can be dropped.
        var cooldownCutoff = DateTime.UtcNow.AddDays(-Math.Max(cooldownDays, 0));
        var cooldownByTicker = await db.StopOutLedgers
            .Where(s => s.UserId == userId && s.StoppedAt >= cooldownCutoff)
            .GroupBy(s => s.Ticker)
            .Select(g => new { Ticker = g.Key, StoppedAt = g.Max(x => x.StoppedAt) })
            .ToDictionaryAsync(x => x.Ticker, x => x.StoppedAt, StringComparer.OrdinalIgnoreCase, ct);

        var positions = await db.UserPortfolioPositions
            .Where(p => p.UserId == userId)
            .OrderBy(p => p.Ticker)
            .ToListAsync(ct);

        // Score the held tickers AND the basket tickers (the basket sweep
        // tells us which sector adds have a high-confidence signal today).
        var heldTickers = positions.Select(p => p.Ticker).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var basketTickers = SectorBasket.Values.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var allTickers = heldTickers.Union(basketTickers).ToList();

        // Resolve sectors for any held tickers we don't have hardcoded.
        // Three-layer chain: hardcoded → DB cache → Lambda → "Unknown".
        var sectorByTicker = await ResolveSectorsAsync(heldTickers, ct);

        // Pull bars from the cache; backfill any ticker with < 200 bars.
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var cutoff = today.AddDays(-450);
        var barsByTicker = new Dictionary<string, List<MarketBar>>(StringComparer.OrdinalIgnoreCase);
        foreach (var ticker in allTickers)
        {
            var bars = await db.TickerDailyCloses
                .Where(b => b.Ticker == ticker && b.Date <= today && b.Date >= cutoff)
                .OrderBy(b => b.Date)
                .Select(b => new MarketBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume))
                .ToListAsync(ct);

            if (bars.Count < 200)
            {
                logger.LogInformation("Portfolio plan: backfilling {Ticker} (have {Count} bars)", ticker, bars.Count);
                try
                {
                    await BackfillAsync(ticker, cutoff, ct);
                    bars = await db.TickerDailyCloses
                        .Where(b => b.Ticker == ticker && b.Date <= today && b.Date >= cutoff)
                        .OrderBy(b => b.Date)
                        .Select(b => new MarketBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume))
                        .ToListAsync(ct);
                }
                catch (Exception e)
                {
                    logger.LogWarning(e, "Backfill failed for {Ticker}; will score with whatever bars we have", ticker);
                }
            }

            barsByTicker[ticker] = bars;
        }

        // Live quotes for held tickers (Finnhub, 15-min delayed on free tier).
        // The plan-time current price needs to reflect intraday moves — using
        // last cached bar close means showing yesterday's price during a live
        // session, which is what the user flagged as stale.
        var livePrices = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
        if (heldTickers.Count > 0)
        {
            var quoteTasks = heldTickers.Select(async t =>
            {
                try
                {
                    var q = await marketData.GetQuoteAsync(t, ct);
                    return (Ticker: t, Quote: q);
                }
                catch
                {
                    return (Ticker: t, Quote: (QuoteSnapshot?)null);
                }
            });
            foreach (var (t, q) in await Task.WhenAll(quoteTasks))
            {
                if (q?.Price is { } p && p > 0) livePrices[t] = p;
            }
        }

        // Score everything in one Lambda call. For held tickers we pass the
        // live quote so the score reflects current pricing; for basket-only
        // tickers (recommendations) the last cached close is fine — they're
        // not in the user's portfolio yet, so freshness matters less.
        var scoreInputs = new List<ScoreInput>();
        foreach (var ticker in allTickers)
        {
            var bars = barsByTicker[ticker];
            if (bars.Count == 0) continue;
            var price = livePrices.TryGetValue(ticker, out var lp) ? lp : bars[^1].Close;
            scoreInputs.Add(new ScoreInput(ticker, bars, price));
        }

        IReadOnlyList<TechnicalScore> scores = Array.Empty<TechnicalScore>();
        if (scoreInputs.Count > 0)
        {
            try
            {
                scores = await marketData.ScoreAsync(scoreInputs, ct);
            }
            catch (Exception e)
            {
                logger.LogError(e, "Portfolio plan: scoring failed; emitting plan without WiseCat signals");
            }
        }
        var scoreByTicker = scores.ToDictionary(s => s.Ticker, s => s, StringComparer.OrdinalIgnoreCase);

        // Build holdings.
        var holdings = new List<PortfolioHoldingDto>();
        decimal invested = 0m;
        foreach (var pos in positions)
        {
            var bars = barsByTicker.TryGetValue(pos.Ticker, out var b) ? b : new List<MarketBar>();
            // Price chain: live quote → last cached bar close → user's cost
            // basis (last-resort fallback so a brand-new ticker doesn't show
            // as $0).
            decimal price;
            if (livePrices.TryGetValue(pos.Ticker, out var lp)) price = lp;
            else if (bars.Count > 0) price = bars[^1].Close;
            else price = pos.CostBasis;
            var marketValue = pos.Shares * price;
            invested += marketValue;
            var unrealizedPct = pos.CostBasis > 0 ? (double)((price / pos.CostBasis) - 1m) : 0.0;
            var sector = sectorByTicker.TryGetValue(pos.Ticker, out var s) ? s : "Unknown";
            var (pBuy, pSell) = ReadProbabilities(scoreByTicker, pos.Ticker, horizon);
            holdings.Add(new PortfolioHoldingDto(
                Ticker: pos.Ticker,
                Sector: sector,
                Shares: pos.Shares,
                CostBasis: pos.CostBasis,
                CurrentPrice: price,
                MarketValue: marketValue,
                PercentOfPortfolio: 0,        // filled below once total known
                UnrealizedReturnPct: unrealizedPct,
                PBuy: pBuy,
                PSell: pSell
            ));
        }

        var cash = cashBalance ?? 0m;
        var total = invested + cash;

        // Patch in PercentOfPortfolio now we know `total`.
        for (int i = 0; i < holdings.Count; i++)
        {
            var h = holdings[i];
            var pct = total > 0 ? (double)(h.MarketValue / total) : 0.0;
            holdings[i] = h with { PercentOfPortfolio = pct };
        }

        // Sector breakdown.
        var sectorBreakdown = holdings
            .GroupBy(h => h.Sector)
            .Select(g => new SectorAllocationDto(
                g.Key,
                g.Sum(h => h.MarketValue),
                total > 0 ? (double)(g.Sum(h => h.MarketValue) / total) : 0.0
            ))
            .OrderByDescending(s => s.MarketValue)
            .ToList();

        var heldBasketSectors = sectorBreakdown
            .Where(s => SectorBasket.ContainsKey(s.Sector))
            .Select(s => s.Sector)
            .ToHashSet();
        var missingSectors = SectorBasket.Keys
            .Where(s => !heldBasketSectors.Contains(s))
            .ToList();

        // -------- Build actions --------
        var actions = new List<PortfolioActionDto>();

        // 1. SELL — rule violations (past stop or strong sell signal).
        var willExit = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in holdings)
        {
            var reasons = new List<string>();
            if (h.UnrealizedReturnPct <= -stopLossPct)
                reasons.Add($"Rule 3 violated: down {h.UnrealizedReturnPct * 100:+0.0;-0.0;0}% (below -{stopLossPct * 100:0}% stop)");
            if (h.UnrealizedReturnPct >= takeProfitPct)
                reasons.Add($"Rule 11 hit: up {h.UnrealizedReturnPct * 100:+0.0}% (at or above +{takeProfitPct * 100:0}% target) — cash out");
            if (h.PSell >= sellSignalPSell)
                reasons.Add($"WiseCat {horizon} p_sell={h.PSell:0.00} ≥ {sellSignalPSell:0.00}");

            if (reasons.Count > 0)
            {
                actions.Add(new PortfolioActionDto(
                    Ticker: h.Ticker,
                    Sector: h.Sector,
                    Kind: PortfolioActionKind.Sell,
                    Shares: h.Shares,
                    Price: h.CurrentPrice,
                    Amount: h.MarketValue,
                    Reason: string.Join("; ", reasons),
                    Bracket: null
                ));
                willExit.Add(h.Ticker);
            }
        }

        // 2. TRIM — over the 10% concentration cap, with a small tolerance band.
        var trimTickers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in holdings)
        {
            if (willExit.Contains(h.Ticker)) continue;
            if (h.PercentOfPortfolio <= positionCapPct * 1.05) continue;
            var targetValue = (decimal)positionCapPct * total;
            var excess = h.MarketValue - targetValue;
            var sharesToSell = h.CurrentPrice > 0 ? excess / h.CurrentPrice : 0m;
            actions.Add(new PortfolioActionDto(
                Ticker: h.Ticker,
                Sector: h.Sector,
                Kind: PortfolioActionKind.Trim,
                Shares: sharesToSell,
                Price: h.CurrentPrice,
                Amount: excess,
                Reason: $"Rule 2: {h.PercentOfPortfolio * 100:0.0}% of portfolio (cap is {positionCapPct * 100:0}%)",
                Bracket: null
            ));
            trimTickers.Add(h.Ticker);
        }

        // 3. BUY — missing sectors. Prefer ones with a high-confidence WiseCat
        //    signal today; otherwise still recommend (with "defer or limit
        //    order" note in the reason).
        var sectorsAfter = holdings
            .Where(h => !willExit.Contains(h.Ticker))
            .Select(h => h.Sector)
            .ToHashSet();
        var targetPerSlot = (decimal)positionCapPct * total;
        foreach (var sector in missingSectors)
        {
            var ticker = SectorBasket[sector];
            var bars = barsByTicker.TryGetValue(ticker, out var b) ? b : new List<MarketBar>();
            var price = bars.Count > 0 ? bars[^1].Close : 0m;
            var (pBuy, _) = ReadProbabilities(scoreByTicker, ticker, horizon);
            var sharesToBuy = price > 0 ? targetPerSlot / price : 0m;

            // Rule 4 — block re-entry if a stop-out is still inside the
            // cooldown window. Surface the date the cooldown lifts so the
            // user knows when to revisit.
            string reason;
            if (cooldownByTicker.TryGetValue(ticker, out var stoppedAt))
            {
                var lifts = stoppedAt.AddDays(cooldownDays);
                reason = $"Rule 4: in cooldown after stop on {stoppedAt:MMM d}. " +
                         $"Re-entry allowed from {lifts:MMM d}. Skip this slot for now.";
                actions.Add(new PortfolioActionDto(
                    Ticker: ticker,
                    Sector: sector,
                    Kind: PortfolioActionKind.Buy,            // BUY tile, null bracket = advisory only
                    Shares: 0m,
                    Price: price,
                    Amount: 0m,
                    Reason: reason,
                    Bracket: null
                ));
                continue;
            }

            reason = pBuy >= entryThresholdPBuy
                ? $"Missing sector + high-confidence buy (p_buy={pBuy:0.00} ≥ {entryThresholdPBuy:0.00})"
                : $"Missing sector (p_buy={pBuy:0.00}, below {entryThresholdPBuy:0.00} — consider limit order or defer)";

            var bracket = BuildBracket(price, sharesToBuy, stopLossPct, takeProfitPct);

            actions.Add(new PortfolioActionDto(
                Ticker: ticker,
                Sector: sector,
                Kind: PortfolioActionKind.Buy,
                Shares: sharesToBuy,
                Price: price,
                Amount: targetPerSlot,
                Reason: reason,
                Bracket: bracket
            ));
        }

        // 4. HOLD — everything else.
        foreach (var h in holdings)
        {
            if (willExit.Contains(h.Ticker) || trimTickers.Contains(h.Ticker)) continue;
            var stopPrice = h.CurrentPrice * (decimal)(1.0 - stopLossPct);
            actions.Add(new PortfolioActionDto(
                Ticker: h.Ticker,
                Sector: h.Sector,
                Kind: PortfolioActionKind.Hold,
                Shares: null,
                Price: h.CurrentPrice,
                Amount: h.MarketValue,
                Reason: $"In good shape. Set stop at {stopPrice:F2} (-{stopLossPct * 100:0}% from current).",
                Bracket: null
            ));
        }

        return new PortfolioPlanDto(
            GeneratedAt: DateTime.UtcNow,
            TotalValue: total,
            InvestedValue: invested,
            CashBalance: cash,
            PositionCount: holdings.Count,
            SectorsCovered: heldBasketSectors.Count,
            MinSectorsRequired: minSectors,
            MissingSectors: missingSectors,
            Holdings: holdings,
            SectorBreakdown: sectorBreakdown,
            Actions: actions
        );
    }

    // ---------- Symbol search enrichment -----------------------------------

    public async Task<IReadOnlyList<EnrichedSymbolMatchDto>> SearchEnrichedAsync(
        Guid userId, string query, int limit, CancellationToken ct = default)
    {
        var trimmed = (query ?? string.Empty).Trim();

        IReadOnlyList<SymbolMatch> hits;
        if (trimmed.Length < 1)
        {
            // Browse mode — no typed query. Universe is the user's held
            // tickers plus the curated mega-cap basket (one rep per
            // sector). Both have cached bars and resolved sectors, so
            // the enrichment loop below stays under a couple of seconds.
            // Scoring more than ~25 tickers per keystroke would dominate
            // the Lambda budget; we cap deliberately at a small universe
            // and rely on Finnhub for the long tail when the user types.
            var holdings = await db.UserPortfolioPositions
                .Where(p => p.UserId == userId)
                .Select(p => p.Ticker)
                .ToListAsync(ct);
            var universe = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var h in holdings) universe.Add(h.ToUpperInvariant());
            foreach (var t in SectorBasket.Values) universe.Add(t.ToUpperInvariant());

            hits = universe
                .OrderBy(s => s, StringComparer.OrdinalIgnoreCase)
                .Select(s => new SymbolMatch(s, string.Empty, "Common Stock"))
                .Take(Math.Clamp(limit, 1, 30))
                .ToList();
        }
        else
        {
            try
            {
                hits = await marketData.SearchSymbolsAsync(trimmed, Math.Clamp(limit, 1, 25), ct);
            }
            catch (Exception e)
            {
                logger.LogWarning(e, "Symbol search failed for query {Query}", trimmed);
                return Array.Empty<EnrichedSymbolMatchDto>();
            }
        }
        if (hits.Count == 0) return Array.Empty<EnrichedSymbolMatchDto>();

        var settings = await strategySettings.GetOrCreateAsync(userId, ct);
        var horizon = settings.EntryHorizon;

        var tickers = hits.Select(h => h.Symbol.ToUpperInvariant()).Distinct().ToList();

        // Sector resolution — cache-only fast path. Falls back to hardcoded
        // overrides; never hits yfinance synchronously (search latency
        // budget is tight). Anything still unresolved stays null and the
        // iOS sector filter just won't include it.
        var sectorMap = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        foreach (var t in tickers)
        {
            var hard = ResolveHardcodedSector(t);
            if (hard is not null) sectorMap[t] = hard;
        }
        var stillMissing = tickers.Where(t => !sectorMap.ContainsKey(t)).ToList();
        if (stillMissing.Count > 0)
        {
            var cached = await db.TickerSectors
                .Where(s => stillMissing.Contains(s.Ticker))
                .ToListAsync(ct);
            foreach (var row in cached)
            {
                sectorMap[row.Ticker] = string.IsNullOrEmpty(row.Sector) ? null : row.Sector;
            }
        }

        // Score only tickers that already have ≥100 cached bars. Backfill
        // would dominate the request time and we're optimizing for keystroke
        // latency, not coverage. The detail view backfills on tap-in.
        const int MinBars = 100;
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var cutoff = today.AddDays(-450);
        var scoreInputs = new List<ScoreInput>();
        foreach (var t in tickers)
        {
            var bars = await db.TickerDailyCloses
                .Where(b => b.Ticker == t && b.Date <= today && b.Date >= cutoff)
                .OrderBy(b => b.Date)
                .Select(b => new MarketBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume))
                .ToListAsync(ct);
            if (bars.Count >= MinBars)
            {
                scoreInputs.Add(new ScoreInput(t, bars, bars[^1].Close));
            }
        }

        var scoreByTicker = new Dictionary<string, TechnicalScore>(StringComparer.OrdinalIgnoreCase);
        if (scoreInputs.Count > 0)
        {
            try
            {
                var scores = await marketData.ScoreAsync(scoreInputs, ct);
                foreach (var s in scores) scoreByTicker[s.Ticker] = s;
            }
            catch (Exception e)
            {
                logger.LogWarning(e, "Search-enrichment scoring failed; returning unscored rows");
            }
        }

        var results = new List<EnrichedSymbolMatchDto>(hits.Count);
        foreach (var h in hits)
        {
            var key = h.Symbol.ToUpperInvariant();
            sectorMap.TryGetValue(key, out var sector);

            double? pBuy = null, pSell = null;
            string? scoredHorizon = null;
            if (scoreByTicker.TryGetValue(key, out var ts))
            {
                var (pb, ps) = ReadProbabilities(scoreByTicker, key, horizon);
                pBuy = pb;
                pSell = ps;
                scoredHorizon = horizon;
            }

            results.Add(new EnrichedSymbolMatchDto(
                Symbol: h.Symbol,
                Description: h.Description,
                Type: h.Type,
                Sector: sector,
                PBuy: pBuy,
                PSell: pSell,
                Horizon: scoredHorizon
            ));
        }
        return results;
    }

    // ---------- helpers -----------------------------------------------------

    private static BracketOrderDto? BuildBracket(
        decimal entryPrice, decimal shares, double stopLossPct, double takeProfitPct)
    {
        if (entryPrice <= 0 || shares <= 0) return null;
        var stopPrice = Math.Round(entryPrice * (decimal)(1.0 - stopLossPct), 4);
        var targetPrice = Math.Round(entryPrice * (decimal)(1.0 + takeProfitPct), 4);
        var riskPerShare = entryPrice - stopPrice;
        if (riskPerShare <= 0) return null;
        var totalRisk = Math.Round(riskPerShare * shares, 2);
        var rMultiple = (double)((targetPrice - entryPrice) / riskPerShare);
        return new BracketOrderDto(
            EntryPrice: Math.Round(entryPrice, 4),
            StopPrice: stopPrice,
            TargetPrice: targetPrice,
            RiskPerShare: Math.Round(riskPerShare, 4),
            TotalRiskDollars: totalRisk,
            RMultiple: rMultiple
        );
    }

    private static string? ResolveHardcodedSector(string ticker)
    {
        return SectorOverrides.TryGetValue(ticker.ToUpperInvariant(), out var s) ? s : null;
    }

    /// <summary>
    /// Resolve every ticker to a sector, three-tier:
    ///   1. Hardcoded large-cap overrides — instant, no I/O.
    ///   2. DB-cached prior lookup (TickerSectors row).
    ///   3. Lambda yfinance .info call. Result is persisted to the cache
    ///      (including "Unknown") so we don't re-hit yfinance next plan.
    /// </summary>
    private async Task<Dictionary<string, string>> ResolveSectorsAsync(
        IEnumerable<string> tickers, CancellationToken ct)
    {
        var resolved = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var stillMissing = new List<string>();
        foreach (var t in tickers.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var hard = ResolveHardcodedSector(t);
            if (hard is not null)
            {
                resolved[t] = hard;
                continue;
            }
            stillMissing.Add(t);
        }

        if (stillMissing.Count == 0) return resolved;

        var cached = await db.TickerSectors
            .Where(s => stillMissing.Contains(s.Ticker))
            .ToListAsync(ct);
        var cachedSet = new HashSet<string>(cached.Select(c => c.Ticker), StringComparer.OrdinalIgnoreCase);
        foreach (var row in cached)
        {
            resolved[row.Ticker] = string.IsNullOrEmpty(row.Sector) ? "Unknown" : row.Sector;
        }

        var lambdaNeeded = stillMissing.Where(t => !cachedSet.Contains(t)).ToList();
        if (lambdaNeeded.Count == 0) return resolved;

        IReadOnlyList<TickerProfile> profiles;
        try
        {
            profiles = await marketData.GetTickerProfilesAsync(lambdaNeeded, ct);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "Sector resolution via Lambda failed; defaulting to Unknown");
            foreach (var t in lambdaNeeded) resolved[t] = "Unknown";
            return resolved;
        }

        var byTicker = profiles.ToDictionary(p => p.Ticker, p => p, StringComparer.OrdinalIgnoreCase);
        var now = DateTime.UtcNow;
        foreach (var t in lambdaNeeded)
        {
            byTicker.TryGetValue(t, out var profile);
            var sector = !string.IsNullOrWhiteSpace(profile?.Sector) ? profile!.Sector! : "Unknown";
            resolved[t] = sector;

            db.TickerSectors.Add(new TickerSector
            {
                Ticker = t.ToUpperInvariant(),
                Sector = sector,
                Name = profile?.Name,
                FetchedAt = now,
            });
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (Exception e)
        {
            // Don't fail the whole plan if the cache write fails — the
            // in-memory `resolved` map is still valid for this request.
            logger.LogWarning(e, "Persisting TickerSectors cache failed");
        }

        return resolved;
    }

    private static (double pBuy, double pSell) ReadProbabilities(
        Dictionary<string, TechnicalScore> scores, string ticker, string horizon)
    {
        if (!scores.TryGetValue(ticker, out var ts)) return (0.0, 0.0);
        var h = horizon.ToUpperInvariant() switch
        {
            "1W" => ts.Horizon1W,
            "1Y" => ts.Horizon1Y,
            _ => ts.Horizon1M,
        };
        return (h.PBuy, h.PSell);
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
}
