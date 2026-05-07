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
    // Per-horizon angle weights (from the multi-horizon plan).
    //   1W: panchang dominates (50%) — fast moon/tithi state matters most;
    //       user/stock transits less, since slow-planet transits barely move
    //       in a week.
    //   1M: balanced — closest to the v1 single-horizon blend.
    //   1Y: user/stock transits dominate (50/40) — slow-planet aspects to
    //       natal charts are the main astrological story over a year;
    //       panchang gets only the slow bucket here (retrogrades).
    private const double WeightUserNatal_1W = 0.30;
    private const double WeightPanchang_1W = 0.50;
    private const double WeightStockNatal_1W = 0.20;

    private const double WeightUserNatal_1M = 0.40;
    private const double WeightPanchang_1M = 0.30;
    private const double WeightStockNatal_1M = 0.30;

    private const double WeightUserNatal_1Y = 0.50;
    private const double WeightPanchang_1Y = 0.10;
    private const double WeightStockNatal_1Y = 0.40;

    private static readonly HashSet<string> Benefics = ["Jupiter", "Venus", "Moon"];
    private static readonly HashSet<string> Malefics = ["Saturn", "Mars", "Sun"];

    public async Task<AstroSignalResult> ComputeAsync(Guid userId, string ticker, DateTime asOfUtc, CancellationToken ct = default)
    {
        if (asOfUtc.Kind != DateTimeKind.Utc) asOfUtc = DateTime.SpecifyKind(asOfUtc, DateTimeKind.Utc);

        var transiting = transit.GetTransitingPositions(asOfUtc);

        // ── 1. User natal transits ────────────────────────────────────────
        // v1 carries the same aspect score across horizons. The horizon
        // differentiation comes from the angle-level weights above; a v2
        // refinement would partition aspects by transiting-planet speed
        // (fast Moon/Mercury at 1W; slow Jupiter/Saturn at 1Y).
        var userAngle = await ComputeUserNatalAngleAsync(userId, transiting, ct);

        // ── 2. Panchang + market-wide ─────────────────────────────────────
        var panchangAngle = ComputePanchangAngle(asOfUtc);

        // ── 3. Stock natal transits ───────────────────────────────────────
        var stockAngle = await ComputeStockNatalAngleAsync(ticker, transiting, ct);

        var angles = new[] { userAngle, panchangAngle, stockAngle };

        var c1W = BlendForHorizon(angles, a => a.Score1W,
            WeightUserNatal_1W, WeightPanchang_1W, WeightStockNatal_1W);
        var c1M = BlendForHorizon(angles, a => a.Score1M,
            WeightUserNatal_1M, WeightPanchang_1M, WeightStockNatal_1M);
        var c1Y = BlendForHorizon(angles, a => a.Score1Y,
            WeightUserNatal_1Y, WeightPanchang_1Y, WeightStockNatal_1Y);

        return new AstroSignalResult(c1W, c1M, c1Y, angles);
    }

    /// <summary>
    /// Weighted blend over user_natal / panchang / stock_natal at one horizon.
    /// Skips angles flagged "no data" and re-normalizes the remaining weights —
    /// matches the v1 behavior so a missing IPO chart doesn't drag the composite
    /// to zero.
    /// </summary>
    private static double BlendForHorizon(
        IReadOnlyList<AstroAngle> angles,
        Func<AstroAngle, double> select,
        double wUserNatal,
        double wPanchang,
        double wStockNatal)
    {
        var totalWeight = 0.0;
        var weighted = 0.0;
        foreach (var a in angles)
        {
            if (a.Highlights.Count > 0 && a.Highlights[0] == "no data") continue;
            var w = a.Name switch
            {
                "user_natal" => wUserNatal,
                "panchang" => wPanchang,
                "stock_natal" => wStockNatal,
                _ => 0.0,
            };
            totalWeight += w;
            weighted += select(a) * w;
        }
        if (totalWeight <= 0.0) return 0.0;
        return Math.Clamp(weighted / totalWeight, -1.0, 1.0);
    }

    private async Task<AstroAngle> ComputeUserNatalAngleAsync(Guid userId, IReadOnlyList<PlanetPosition> transiting, CancellationToken ct)
    {
        try
        {
            var birth = await profileQuery.GetBirthInfoAsync(userId, ct);
            if (birth.BirthDate is null || birth.BirthTime is null)
            {
                return new AstroAngle("user_natal", 0.0, 0.0, 0.0, ["no data"]);
            }
            if (!TimeOnly.TryParseExact(birth.BirthTime, "HH:mm", out var bt))
            {
                return new AstroAngle("user_natal", 0.0, 0.0, 0.0, ["no data"]);
            }
            var (lat, lon) = ParseBirthPlace(birth.BirthPlace);
            var birthUtc = BirthTimeResolver.ResolveBirthUtc(birth.BirthDate.Value, bt, lat, lon);

            var natal = ComputeNatalPositions(birthUtc);
            var aspects = transit.ComputeAspects(transiting, natal);

            var (score, highlights) = ScoreAspects(aspects);
            // v1: same score across horizons. See the comment in ComputeAsync.
            return new AstroAngle("user_natal", score, score, score, highlights);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "user natal angle failed for {UserId}", userId);
            return new AstroAngle("user_natal", 0.0, 0.0, 0.0, ["no data"]);
        }
    }

    /// <summary>
    /// Panchang score is the sum of a fast bucket (tithi, nakshatra) and a
    /// slow bucket (retrogrades). Per horizon:
    ///   1W → fast only — tithi/nakshatra change every 1-2 days, retrogrades
    ///        last weeks-to-months and don't move within a 1W window.
    ///   1M → fast + slow — matches the v1 panchang behavior.
    ///   1Y → slow only — retrogrades shape the year's calendar; tithi cycles
    ///        average out over 12 months and contribute noise, not signal.
    /// </summary>
    private AstroAngle ComputePanchangAngle(DateTime asOfUtc)
    {
        var highlights = new List<string>();
        var fastScore = 0.0;
        var slowScore = 0.0;

        var panchang = VedicCalendar.GetPanchang(asOfUtc);

        // Fast bucket: tithi + Moon nakshatra. Tithi changes every ~1.9 days;
        // nakshatra changes every ~1.25 days.
        if (panchang.Tithi.StartsWith("Shukla", StringComparison.OrdinalIgnoreCase))
        {
            fastScore += 0.3;
            highlights.Add("waxing moon (Shukla paksha)");
        }
        else if (panchang.Tithi.StartsWith("Krishna", StringComparison.OrdinalIgnoreCase))
        {
            fastScore -= 0.2;
            highlights.Add("waning moon (Krishna paksha)");
        }

        // Slow bucket: retrogrades. Mercury retrograde lasts ~3 weeks;
        // Jupiter ~4 months; Saturn ~4.5 months.
        if (PlanetaryPositions.IsRetrograde("Mercury", asOfUtc))
        {
            slowScore -= 0.4;
            highlights.Add("Mercury retrograde");
        }
        if (PlanetaryPositions.IsRetrograde("Jupiter", asOfUtc))
        {
            slowScore -= 0.1;
            highlights.Add("Jupiter retrograde");
        }
        if (PlanetaryPositions.IsRetrograde("Saturn", asOfUtc))
        {
            slowScore -= 0.1;
            highlights.Add("Saturn retrograde");
        }

        // Nakshatra quality is qualitative — fold into highlights only (no score).
        if (!string.IsNullOrEmpty(panchang.NakshatraQuality))
        {
            highlights.Add($"Moon: {panchang.Nakshatra} ({panchang.NakshatraQuality})");
        }

        var score1W = Math.Clamp(fastScore, -1.0, 1.0);
        var score1M = Math.Clamp(fastScore + slowScore, -1.0, 1.0);
        var score1Y = Math.Clamp(slowScore, -1.0, 1.0);

        return new AstroAngle("panchang", score1W, score1M, score1Y, highlights);
    }

    private async Task<AstroAngle> ComputeStockNatalAngleAsync(string ticker, IReadOnlyList<PlanetPosition> transiting, CancellationToken ct)
    {
        try
        {
            var view = await stockChart.GetOrCreateAsync(ticker, ct);
            if (view is null)
            {
                return new AstroAngle("stock_natal", 0.0, 0.0, 0.0, ["no data"]);
            }

            var natal = ComputeNatalPositions(view.IpoUtc);
            var aspects = transit.ComputeAspects(transiting, natal);
            var (score, highlights) = ScoreAspects(aspects);
            return new AstroAngle("stock_natal", score, score, score, highlights);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "stock natal angle failed for {Ticker}", ticker);
            return new AstroAngle("stock_natal", 0.0, 0.0, 0.0, ["no data"]);
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
        var parts = birthPlace.Split(',', 2, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return (null, null);
        if (!double.TryParse(parts[0].Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var lat)) return (null, null);
        if (!double.TryParse(parts[1].Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var lon)) return (null, null);
        return (lat, lon);
    }
}
