namespace ShantiSangha.Trading.Contracts;

// ---------- Position CRUD ---------------------------------------------------

public record PortfolioPositionDto(
    string Ticker,
    decimal Shares,
    decimal CostBasis,         // per share
    DateTime UpdatedAt
);

public record SavePortfolioRequest(
    IReadOnlyList<SavePortfolioPosition> Positions,
    decimal? CashBalance
);

public record SavePortfolioPosition(
    string Ticker,
    decimal Shares,
    decimal CostBasis
);

// ---------- Plan output -----------------------------------------------------
//
// The plan is the iOS-renderable read of the audit. Two parallel sections:
// `Holdings` (everything currently owned, scored) and `Actions` (what to do).
// Keep this shape stable — iOS rendering keys off ActionKind.

public enum PortfolioActionKind
{
    Sell = 0,          // Rule violation: exit immediately
    Trim = 1,          // Over concentration cap, sell down to 10%
    Buy = 2,           // Missing sector or high-confidence signal — add
    Hold = 3,          // In good shape, no action this cycle
}

public record PortfolioActionDto(
    string Ticker,
    string Sector,
    PortfolioActionKind Kind,
    decimal? Shares,           // shares to sell/buy. null for hold.
    decimal? Price,            // current price; reference for the user
    decimal? Amount,           // dollar amount of the action
    string Reason,             // human-readable explanation
    BracketOrderDto? Bracket   // populated on BUY actions; null otherwise
);

public record PortfolioHoldingDto(
    string Ticker,
    string Sector,
    decimal Shares,
    decimal CostBasis,
    decimal CurrentPrice,
    decimal MarketValue,
    double PercentOfPortfolio,
    double UnrealizedReturnPct,
    double PBuy,
    double PSell
);

public record SectorAllocationDto(
    string Sector,
    decimal MarketValue,
    double PercentOfPortfolio
);

public record PortfolioPlanDto(
    DateTime GeneratedAt,
    decimal TotalValue,
    decimal InvestedValue,
    decimal CashBalance,
    int PositionCount,
    int SectorsCovered,
    int MinSectorsRequired,
    IReadOnlyList<string> MissingSectors,
    IReadOnlyList<PortfolioHoldingDto> Holdings,
    IReadOnlyList<SectorAllocationDto> SectorBreakdown,
    IReadOnlyList<PortfolioActionDto> Actions
);

// ---------- Per-user strategy settings (Rules 1–11 constants) -------------

public record StrategySettingsDto(
    decimal StopLossPct,           // Rule 3
    decimal TakeProfitPct,         // Rule 11
    decimal EntryThresholdPBuy,    // Rule 10
    string EntryHorizon,           // "1W" | "1M" | "1Y"
    int CooldownDays,              // Rule 4
    decimal PositionCapPct,        // Rule 2
    int MinSectors,                // Rule 1
    decimal SellSignalPSell,       // exit on momentum reversal
    DateTime UpdatedAt
);

public record UpdateStrategySettingsRequest(
    decimal? StopLossPct,
    decimal? TakeProfitPct,
    decimal? EntryThresholdPBuy,
    string? EntryHorizon,
    int? CooldownDays,
    decimal? PositionCapPct,
    int? MinSectors,
    decimal? SellSignalPSell
);

// ---------- Bracket-order prep (BUY action enrichment) ---------------------

/// <summary>
/// Concrete numbers for placing a bracket order at the broker: entry,
/// stop, target, dollar risk, R-multiple. Populated on BUY actions only.
/// All values are advisory — the user still executes at their broker.
/// </summary>
public record BracketOrderDto(
    decimal EntryPrice,        // current price; reference for limit-order placement
    decimal StopPrice,         // entry * (1 - stopLossPct)
    decimal TargetPrice,       // entry * (1 + takeProfitPct)
    decimal RiskPerShare,      // entry - stopPrice (always positive)
    decimal TotalRiskDollars,  // riskPerShare * shares
    double  RMultiple          // (target - entry) / (entry - stopPrice)
);

// ---------- Search enrichment ----------------------------------------------

/// <summary>
/// Symbol-search hit enriched with sector (from the TickerSectors cache +
/// hardcoded overrides — never hits yfinance synchronously) and p_buy /
/// p_sell at the user's entry horizon (null when not enough bars are
/// cached locally to score; the detail view backfills on tap-in).
/// </summary>
public record EnrichedSymbolMatchDto(
    string Symbol,
    string Description,
    string Type,
    string? Sector,
    double? PBuy,
    double? PSell,
    string? Horizon          // which horizon the scores reflect, if scored
);

// ---------- Backtest (Rules-sheet preview) ---------------------------------

/// <summary>
/// Returned by POST /api/wisecat/strategy/backtest. Summary stats over a
/// fixed multi-regime window so the user can preview the envelope of
/// their current rule constants before saving.
/// </summary>
public record StrategyBacktestResultDto(
    string Window,                  // "2014-2024" etc — the regime span backtested
    double AnnualizedReturnPct,     // e.g. 0.082 = 8.2%/yr
    double MaxDrawdownPct,          // negative; e.g. -0.18 = -18%
    int Trades,
    double WinRatePct,              // 0..1
    double SharpeApprox,            // mean / stdev of monthly returns × sqrt(12)
    string Notes                    // free-form caveats from the runner
);

// ---------- IBKR broker link -----------------------------------------------

/// <summary>
/// Shape returned by GET /api/wisecat/ibkr/status. When `Status` is
/// Disconnected, the user has not linked an IBKR account yet — most of
/// the fields are zero/null. When Active, positions in
/// UserPortfolioPositions are broker-sourced and manual edits are blocked.
/// </summary>
public record IbkrStatusDto(
    string Status,                   // Active | NeedsReauth | Disconnected | Suspended
    string? IbkrAccountId,           // IBKR account number, e.g. "U1234567"
    DateTime? LinkedAt,
    DateTime? LastSyncAt,
    DateTime? LastSuccessfulSyncAt,
    string? LastErrorMessage,
    string BaseCurrency,
    decimal CashBalance,
    DateTime? CashBalanceAt
);

/// <summary>
/// Sync result envelope returned by POST /ibkr/link and /ibkr/resync.
/// `Skipped` covers positions rejected by the v1 filters (non-STK, non-base
/// currency, or short positions) — surfaced so the user can see the gap
/// between IBKR app holdings and what WiseCat will trade against.
/// </summary>
public record IbkrSyncResultDto(
    bool Success,
    int PositionsImported,
    int PositionsSkipped,
    decimal CashBalance,
    string BaseCurrency,
    string Status,
    string? ErrorMessage
);
