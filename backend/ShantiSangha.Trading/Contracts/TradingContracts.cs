using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Contracts;

public record AddWatchlistRequest(string Ticker);

public record WatchlistItemDto(
    string Ticker,
    DateTime AddedAt
);

public record StrategyContributionDto(string Name, double Value, double Contribution, double Weight);

public record AstroAngleScoreDto(string Angle, double Score, IReadOnlyList<string> Highlights);

/// <summary>
/// One horizon's read of a (ticker, date): action, composite, conviction,
/// the technical and astro split, and the per-strategy contributions that
/// produced this horizon's technical score.
/// </summary>
public record HorizonReadDto(
    string Action,            // "Buy" | "Sell" | "Hold"
    double Conviction,
    double TechnicalScore,
    double AstroScore,
    double CompositeScore,
    IReadOnlyList<StrategyContributionDto> TechnicalSignals
);

/// <summary>
/// One signal per (user, ticker, date), carrying three horizon reads
/// (1W / 1M / 1Y). The top-level Action / *Score fields mirror the 1M
/// horizon for consumers that haven't migrated to the per-horizon API.
/// </summary>
public record TradingSignalDto(
    string Ticker,
    DateOnly Date,
    string Action,            // "Buy" | "Sell" | "Hold" — equals Horizon1M.Action
    double Conviction,        // equals Horizon1M.Conviction
    double TechnicalScore,    // equals Horizon1M.TechnicalScore
    double AstroScore,        // equals Horizon1M.AstroScore
    double CompositeScore,    // equals Horizon1M.CompositeScore
    decimal? Price,
    IReadOnlyList<StrategyContributionDto> TechnicalSignals, // equals Horizon1M.TechnicalSignals
    IReadOnlyList<AstroAngleScoreDto> AstroAngles,
    HorizonReadDto Horizon1W,
    HorizonReadDto Horizon1M,
    HorizonReadDto Horizon1Y
);

/// <summary>
/// Persisted JSON shape inside TradingSignal.ReasoningJson.
/// Per-horizon technical contributions plus the (horizon-shared) astro angles.
/// </summary>
public record SignalReasoning(
    IReadOnlyList<StrategyContributionDto> Technical1W,
    IReadOnlyList<StrategyContributionDto> Technical1M,
    IReadOnlyList<StrategyContributionDto> Technical1Y,
    IReadOnlyList<AstroAngleScoreDto> Astro
);
