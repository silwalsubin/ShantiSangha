namespace ShantiSangha.Trading.Services;

public record PlanetPosition(string Planet, double SiderealLongitude, int RashiIndex);

public record TransitAspect(
    string TransitPlanet,
    string NatalPlanet,
    string AspectName,    // "conjunction", "7th", "4th", "8th", "5th", "9th", "3rd", "10th"
    int HousesAhead,      // 1..12 from natal planet's rashi to transit planet's rashi
    double OrbDegrees,    // angular distance from exact (lower = stronger)
    double Strength       // [0, 1] — strength of the aspect
);

/// <summary>
/// Computes Vedic graha drishti (planetary aspects) from transiting planets to
/// natal-chart positions. Used both against the user's natal chart and against
/// a stock's IPO chart.
///
/// Vedic aspects:
/// - All planets aspect the 7th house from themselves.
/// - Mars also aspects 4th and 8th.
/// - Jupiter also aspects 5th and 9th.
/// - Saturn also aspects 3rd and 10th.
/// </summary>
public interface ITransitAspectService
{
    /// <summary>Sidereal positions of the 7 classical planets at the given UTC instant.</summary>
    IReadOnlyList<PlanetPosition> GetTransitingPositions(DateTime utc);

    /// <summary>
    /// Aspects from each transiting planet to each natal planet. Strength is
    /// 1.0 at exact aspect (orb 0°) and decays linearly to 0.0 at orb 8°.
    /// </summary>
    IReadOnlyList<TransitAspect> ComputeAspects(
        IReadOnlyList<PlanetPosition> transiting,
        IReadOnlyList<PlanetPosition> natal);
}
