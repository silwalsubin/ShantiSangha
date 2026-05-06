using ShantiSangha.Jyotish.Services;

namespace ShantiSangha.Trading.Services;

public class TransitAspectService : ITransitAspectService
{
    private const double OrbCutoffDegrees = 8.0;

    private static readonly string[] All = ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn"];

    // Vedic special aspects per planet — house numbers ahead (1-indexed). 7 is universal and added separately.
    private static readonly Dictionary<string, int[]> SpecialHouses = new()
    {
        ["Mars"] = [4, 8],
        ["Jupiter"] = [5, 9],
        ["Saturn"] = [3, 10],
    };

    public IReadOnlyList<PlanetPosition> GetTransitingPositions(DateTime utc)
    {
        if (utc.Kind != DateTimeKind.Utc) utc = DateTime.SpecifyKind(utc, DateTimeKind.Utc);

        var results = new List<PlanetPosition>(All.Length);
        foreach (var p in All)
        {
            var trop = p switch
            {
                "Sun" => VedicCalendar.GetTropicalSunLongitude(utc),
                "Moon" => VedicCalendar.GetTropicalMoonLongitude(utc),
                "Mercury" => PlanetaryPositions.GetTropicalMercuryLongitude(utc),
                "Venus" => PlanetaryPositions.GetTropicalVenusLongitude(utc),
                "Mars" => PlanetaryPositions.GetTropicalMarsLongitude(utc),
                "Jupiter" => PlanetaryPositions.GetTropicalJupiterLongitude(utc),
                "Saturn" => PlanetaryPositions.GetTropicalSaturnLongitude(utc),
                _ => 0.0,
            };
            var sid = VedicCalendar.ToSidereal(trop, utc);
            results.Add(new PlanetPosition(p, sid, VedicCalendar.GetRashiIndex(sid)));
        }
        return results;
    }

    public IReadOnlyList<TransitAspect> ComputeAspects(
        IReadOnlyList<PlanetPosition> transiting,
        IReadOnlyList<PlanetPosition> natal)
    {
        var aspects = new List<TransitAspect>();
        foreach (var t in transiting)
        {
            foreach (var n in natal)
            {
                // Houses ahead from natal rashi to transit rashi (1..12, where 1 = same rashi = conjunction)
                var housesAhead = ((t.RashiIndex - n.RashiIndex + 12) % 12) + 1;

                // Conjunction: same sign, considered an aspect-by-association.
                if (housesAhead == 1)
                {
                    var orb = Math.Abs(NormalizedDelta(t.SiderealLongitude, n.SiderealLongitude));
                    if (orb <= OrbCutoffDegrees)
                    {
                        aspects.Add(new TransitAspect(t.Planet, n.Planet, "conjunction", 1, orb, StrengthFromOrb(orb)));
                    }
                    continue;
                }

                // 7th-house aspect: all planets cast it.
                if (housesAhead == 7)
                {
                    var orb = OrbForHouseAspect(t.SiderealLongitude, n.SiderealLongitude, 6);
                    if (orb <= OrbCutoffDegrees)
                    {
                        aspects.Add(new TransitAspect(t.Planet, n.Planet, "7th", 7, orb, StrengthFromOrb(orb)));
                    }
                    continue;
                }

                // Special aspects per planet.
                if (SpecialHouses.TryGetValue(t.Planet, out var houses))
                {
                    foreach (var h in houses)
                    {
                        if (housesAhead != h) continue;
                        var orb = OrbForHouseAspect(t.SiderealLongitude, n.SiderealLongitude, h - 1);
                        if (orb <= OrbCutoffDegrees)
                        {
                            aspects.Add(new TransitAspect(t.Planet, n.Planet, $"{h}th", h, orb, StrengthFromOrb(orb)));
                        }
                    }
                }
            }
        }
        return aspects;
    }

    /// <summary>Normalize ecliptic longitude difference to [-180, 180].</summary>
    private static double NormalizedDelta(double a, double b)
    {
        var d = (a - b) % 360.0;
        if (d > 180.0) d -= 360.0;
        if (d < -180.0) d += 360.0;
        return d;
    }

    /// <summary>Orb between transit's longitude and the exact aspect point (n×30° from natal).</summary>
    private static double OrbForHouseAspect(double transitLon, double natalLon, int houseOffsetZeroBased)
    {
        var exactPoint = (natalLon + houseOffsetZeroBased * 30.0 + 15.0) % 360.0; // mid-sign
        return Math.Abs(NormalizedDelta(transitLon, exactPoint));
    }

    private static double StrengthFromOrb(double orbDegrees)
    {
        if (orbDegrees >= OrbCutoffDegrees) return 0.0;
        return 1.0 - (orbDegrees / OrbCutoffDegrees);
    }
}
