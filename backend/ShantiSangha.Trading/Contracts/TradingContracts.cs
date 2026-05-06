using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Contracts;

public record AddWatchlistRequest(string Ticker);

public record WatchlistItemDto(
    string Ticker,
    DateTime AddedAt
);

public record StrategyContributionDto(string Name, double Value, double Contribution);

public record AstroAngleScoreDto(string Angle, double Score, IReadOnlyList<string> Highlights);

public record TradingSignalDto(
    string Ticker,
    DateOnly Date,
    string Action,            // "Buy" | "Sell" | "Hold"
    double Conviction,
    double TechnicalScore,
    double AstroScore,
    double CompositeScore,
    decimal? Price,
    IReadOnlyList<StrategyContributionDto> TechnicalSignals,
    IReadOnlyList<AstroAngleScoreDto> AstroAngles
);

public record SignalReasoning(
    IReadOnlyList<StrategyContributionDto> Technical,
    IReadOnlyList<AstroAngleScoreDto> Astro
);
