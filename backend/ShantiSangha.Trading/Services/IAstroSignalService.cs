namespace ShantiSangha.Trading.Services;

public record AstroAngle(
    string Name,
    double Score1W,
    double Score1M,
    double Score1Y,
    IReadOnlyList<string> Highlights)
{
    /// <summary>Legacy single-horizon view = the 1M score.</summary>
    public double Score => Score1M;
}

public record AstroSignalResult(
    double Composite1W,
    double Composite1M,
    double Composite1Y,
    IReadOnlyList<AstroAngle> Angles)
{
    /// <summary>Legacy single-horizon view = the 1M composite.</summary>
    public double CompositeScore => Composite1M;
}

/// <summary>
/// Combines three astrological angles into per-horizon scores in [-1, 1]:
///   1) Transits to the user's natal chart.
///   2) Current panchang + market-wide bias (moon phase, retrogrades).
///   3) Transits to the stock's IPO natal chart (skipped if no chart data).
///
/// Each horizon (1W / 1M / 1Y) blends the angles with horizon-specific
/// weights, and the panchang score is split into a fast bucket (tithi,
/// nakshatra) and a slow bucket (retrogrades) — only the fast bucket
/// contributes at 1W and only the slow bucket at 1Y.
/// </summary>
public interface IAstroSignalService
{
    Task<AstroSignalResult> ComputeAsync(Guid userId, string ticker, DateTime asOfUtc, CancellationToken ct = default);
}
