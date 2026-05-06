using Microsoft.Extensions.Logging;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Trading.Services;

public class AstroSignalService(
    IProfileQueryService profileQuery,
    IStockChartService stockChart,
    ITransitAspectService transit,
    ILogger<AstroSignalService> logger) : IAstroSignalService
{
    // Weights from the plan: user natal 40%, panchang 30%, stock natal 30%.
    private const double WeightUserNatal = 0.40;
    private const double WeightPanchang = 0.30;
    private const double WeightStockNatal = 0.30;

    private static readonly HashSet<string> Benefics = ["Jupiter", "Venus", "Moon"];
    private static readonly HashSet<string> Malefics = ["Saturn", "Mars", "Sun"];

    public async Task<AstroSignalResult> ComputeAsync(Guid userId, string ticker, DateTime asOfUtc, CancellationToken ct = default)
    {
        if (asOfUtc.Kind != DateTimeKind.Utc) asOfUtc = DateTime.SpecifyKind(asOfUtc, DateTimeKind.Utc);

        var transiting = transit.GetTransitingPositions(asOfUtc);
        var angles = new List<AstroAngle>(3);

        // ── 1. User natal transits ────────────────────────────────────────
        var userAngle = await ComputeUserNatalAngleAsync(userId, transiting, ct);
        angles.Add(userAngle);

        // ── 2. Panchang + market-wide ─────────────────────────────────────
        angles.Add(ComputePanchangAngle(asOfUtc, transiting));

        // ── 3. Stock natal transits ───────────────────────────────────────
        var stockAngle = await ComputeStockNatalAngleAsync(ticker, transiting, ct);
        angles.Add(stockAngle);

        // Re-normalize weights when an angle is unavailable (returned 0 with a "no data" highlight).
        var totalWeight = 0.0;
        var weighted = 0.0;
        foreach (var a in angles)
        {
            var weight = a.Name switch
            {
                "user_natal" => WeightUserNatal,
                "panchang" => WeightPanchang,
                "stock_natal" => WeightStockNatal,
                _ => 0.0,
            };
            if (a.Highlights.Count > 0 && a.Highlights[0] == "no data") continue;
            totalWeight += weight;
            weighted += a.Score * weight;
        }

        var composite = totalWeight > 0 ? weighted / totalWeight : 0.0;
        composite = Math.Clamp(composite, -1.0, 1.0);
        return new AstroSignalResult(composite, angles);
    }

    private async Task<AstroAngle> ComputeUserNatalAngleAsync(Guid userId, IReadOnlyList<PlanetPosition> transiting, CancellationToken ct)
    {
        try
        {
            var birth = await profileQuery.GetBirthInfoAsync(userId, ct);
            if (birth.BirthDate is null || birth.BirthTime is null)
            {
                return new AstroAngle("user_natal", 0.0, ["no data"]);
            }
            if (!TimeOnly.TryParseExact(birth.BirthTime, "HH:mm", out var bt))
            {
                return new AstroAngle("user_natal", 0.0, ["no data"]);
            }
            var (lat, lon) = ParseBirthPlace(birth.BirthPlace);
            var birthUtc = BirthTimeResolver.ResolveBirthUtc(birth.BirthDate.Value, bt, lat, lon);

            var natal = ComputeNatalPositions(birthUtc);
            var aspects = transit.ComputeAspects(transiting, natal);

            // Score: weight aspects by transit-planet polarity. Benefic aspect to natal benefic +; malefic aspect to natal benefic -.
            var (score, highlights) = ScoreAspects(aspects);
            return new AstroAngle("user_natal", score, highlights);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "user natal angle failed for {UserId}", userId);
            return new AstroAngle("user_natal", 0.0, ["no data"]);
        }
    }

    private AstroAngle ComputePanchangAngle(DateTime asOfUtc, IReadOnlyList<PlanetPosition> transiting)
    {
        var highlights = new List<string>();
        var score = 0.0;

        var panchang = VedicCalendar.GetPanchang(asOfUtc);

        // Tithi quality: bright fortnight (Shukla) is auspicious; dark (Krishna) cautious.
        // GetPanchang returns Tithi as "Shukla N" or "Krishna N" — heuristic on prefix.
        if (panchang.Tithi.StartsWith("Shukla", StringComparison.OrdinalIgnoreCase))
        {
            score += 0.3;
            highlights.Add("waxing moon (Shukla paksha)");
        }
        else if (panchang.Tithi.StartsWith("Krishna", StringComparison.OrdinalIgnoreCase))
        {
            score -= 0.2;
            highlights.Add("waning moon (Krishna paksha)");
        }

        // Mercury retrograde — bearish bias for new entries.
        if (PlanetaryPositions.IsRetrograde("Mercury", asOfUtc))
        {
            score -= 0.4;
            highlights.Add("Mercury retrograde");
        }

        // Jupiter retrograde — slight cautious bias for expansion.
        if (PlanetaryPositions.IsRetrograde("Jupiter", asOfUtc))
        {
            score -= 0.1;
            highlights.Add("Jupiter retrograde");
        }

        // Saturn retrograde — historically associated with consolidation/decline phases.
        if (PlanetaryPositions.IsRetrograde("Saturn", asOfUtc))
        {
            score -= 0.1;
            highlights.Add("Saturn retrograde");
        }

        // Moon's nakshatra quality — fold the qualitative descriptor into highlights only.
        if (!string.IsNullOrEmpty(panchang.NakshatraQuality))
        {
            highlights.Add($"Moon: {panchang.Nakshatra} ({panchang.NakshatraQuality})");
        }

        return new AstroAngle("panchang", Math.Clamp(score, -1.0, 1.0), highlights);
    }

    private async Task<AstroAngle> ComputeStockNatalAngleAsync(string ticker, IReadOnlyList<PlanetPosition> transiting, CancellationToken ct)
    {
        try
        {
            var view = await stockChart.GetOrCreateAsync(ticker, ct);
            if (view is null)
            {
                return new AstroAngle("stock_natal", 0.0, ["no data"]);
            }

            var natal = ComputeNatalPositions(view.IpoUtc);
            var aspects = transit.ComputeAspects(transiting, natal);
            var (score, highlights) = ScoreAspects(aspects);
            return new AstroAngle("stock_natal", score, highlights);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "stock natal angle failed for {Ticker}", ticker);
            return new AstroAngle("stock_natal", 0.0, ["no data"]);
        }
    }

    private static (double Score, List<string> Highlights) ScoreAspects(IReadOnlyList<TransitAspect> aspects)
    {
        var raw = 0.0;
        var n = 0;
        var highlights = new List<string>();

        foreach (var a in aspects)
        {
            var transitIsBenefic = Benefics.Contains(a.TransitPlanet);
            var transitIsMalefic = Malefics.Contains(a.TransitPlanet);
            var natalIsBenefic = Benefics.Contains(a.NatalPlanet);
            var natalIsMalefic = Malefics.Contains(a.NatalPlanet);

            // Benefic transit to a benefic → strongly positive.
            // Benefic transit to a malefic → mildly positive (softens the malefic).
            // Malefic transit to a benefic → negative (afflicts the benefic).
            // Malefic transit to another malefic → negative (compounds).
            double polarity;
            if (transitIsBenefic && natalIsBenefic) polarity = 1.0;
            else if (transitIsBenefic && natalIsMalefic) polarity = 0.4;
            else if (transitIsMalefic && natalIsBenefic) polarity = -1.0;
            else if (transitIsMalefic && natalIsMalefic) polarity = -0.5;
            else polarity = 0.0; // neutrals (Mercury), safety guard

            raw += polarity * a.Strength;
            n++;

            if (a.Strength > 0.5)
            {
                highlights.Add($"{a.TransitPlanet} {a.AspectName} natal {a.NatalPlanet} (orb {a.OrbDegrees:F1}°)");
            }
        }

        if (n == 0) return (0.0, highlights);
        // Average and rescale so a fully-benefic sweep saturates near +1 and full-malefic near -1.
        var avg = raw / n;
        var score = Math.Clamp(avg * 2.0, -1.0, 1.0);
        return (score, highlights);
    }

    private static IReadOnlyList<PlanetPosition> ComputeNatalPositions(DateTime utc)
    {
        if (utc.Kind != DateTimeKind.Utc) utc = DateTime.SpecifyKind(utc, DateTimeKind.Utc);

        string[] all = ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn"];
        var results = new List<PlanetPosition>(all.Length);
        foreach (var p in all)
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

    private static (double? Lat, double? Lon) ParseBirthPlace(string? birthPlace)
    {
        if (string.IsNullOrWhiteSpace(birthPlace)) return (null, null);
        // Profile.BirthPlace is stored as "lat,lon" (per ProfileQueryService).
        var parts = birthPlace.Split(',', 2, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return (null, null);
        if (!double.TryParse(parts[0].Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var lat)) return (null, null);
        if (!double.TryParse(parts[1].Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var lon)) return (null, null);
        return (lat, lon);
    }
}
