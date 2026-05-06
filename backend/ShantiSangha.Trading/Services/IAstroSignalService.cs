namespace ShantiSangha.Trading.Services;

public record AstroAngle(string Name, double Score, IReadOnlyList<string> Highlights);

public record AstroSignalResult(double CompositeScore, IReadOnlyList<AstroAngle> Angles);

/// <summary>
/// Combines three astrological angles into a single score in [-1, 1]:
///   1) Transits to the user's natal chart.
///   2) Current panchang + market-wide bias (moon phase, mercury retrograde).
///   3) Transits to the stock's IPO natal chart (skipped if no chart data).
/// </summary>
public interface IAstroSignalService
{
    Task<AstroSignalResult> ComputeAsync(Guid userId, string ticker, DateTime asOfUtc, CancellationToken ct = default);
}
