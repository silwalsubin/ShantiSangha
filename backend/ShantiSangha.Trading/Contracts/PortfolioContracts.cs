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
    string Reason              // human-readable explanation
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
    double PBuy1M,
    double PSell1M
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
