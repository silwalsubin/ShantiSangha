namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Computes the set of Jyotish signatures that apply to a user's birth chart.
/// Signatures are lowercase tokens like "moon_in_vrishabha" or "saturn_in_h7"
/// that match the corpus indexing scheme.
/// </summary>
public static class ChartSignatures
{
    // Sanskrit rashi names in zero-indexed order — matches VedicCalendar.
    private static readonly string[] RashiSanskrit =
    [
        "mesha", "vrishabha", "mithuna", "karka",
        "simha", "kanya", "tula", "vrischika",
        "dhanu", "makara", "kumbha", "meena"
    ];

    private static readonly string[] NakshatraSanskrit =
    [
        "ashwini", "bharani", "krittika", "rohini",
        "mrigashirsha", "ardra", "punarvasu", "pushya",
        "ashlesha", "magha", "purva_phalguni", "uttara_phalguni",
        "hasta", "chitra", "swati", "vishakha",
        "anuradha", "jyeshtha", "mula", "purva_ashadha",
        "uttara_ashadha", "shravana", "dhanishta", "shatabhisha",
        "purva_bhadrapada", "uttara_bhadrapada", "revati"
    ];

    /// <summary>
    /// Computes all signatures applicable to a natal chart from birth data.
    /// Requires birth date, time, and coordinates for full signature set;
    /// gracefully degrades if any are missing.
    /// </summary>
    public static IReadOnlyList<string> ComputeNatalSignatures(
        DateOnly birthDate,
        TimeOnly? birthTime,
        double? latitude,
        double? longitude,
        DateTime? now = null)
    {
        var signatures = new HashSet<string>();

        if (birthTime is null) return signatures.ToList();

        var birthUtc = BirthTimeResolver.ResolveBirthUtc(birthDate, birthTime.Value, latitude, longitude);

        // Compute sidereal positions for the natal chart
        var sunTropical = VedicCalendar.GetTropicalSunLongitude(birthUtc);
        var moonTropical = VedicCalendar.GetTropicalMoonLongitude(birthUtc);

        var sunSidereal = VedicCalendar.ToSidereal(sunTropical, birthUtc);
        var moonSidereal = VedicCalendar.ToSidereal(moonTropical, birthUtc);

        // Rashi placements for Sun, Moon
        signatures.Add($"sun_in_{RashiSanskrit[VedicCalendar.GetRashiIndex(sunSidereal)]}");
        signatures.Add($"moon_in_{RashiSanskrit[VedicCalendar.GetRashiIndex(moonSidereal)]}");

        // Moon's nakshatra
        signatures.Add($"moon_in_{NakshatraSanskrit[VedicCalendar.GetNakshatraIndex(moonSidereal)]}");

        // Ascendant — only if we have lat/lon
        double? ascSidereal = null;
        string? lagnaRashi = null;
        if (latitude.HasValue && longitude.HasValue)
        {
            var ascTropical = VedicCalendar.GetTropicalAscendant(birthUtc, latitude.Value, longitude.Value);
            ascSidereal = VedicCalendar.ToSidereal(ascTropical, birthUtc);
            lagnaRashi = RashiSanskrit[VedicCalendar.GetRashiIndex(ascSidereal.Value)];
            signatures.Add($"lagna_in_{lagnaRashi}");
        }

        var planetLongitudes = new (string Lower, string Cap, double Tropical)[]
        {
            ("sun", "Sun", sunTropical),
            ("moon", "Moon", moonTropical),
            ("mercury", "Mercury", PlanetaryPositions.GetTropicalMercuryLongitude(birthUtc)),
            ("venus", "Venus", PlanetaryPositions.GetTropicalVenusLongitude(birthUtc)),
            ("mars", "Mars", PlanetaryPositions.GetTropicalMarsLongitude(birthUtc)),
            ("jupiter", "Jupiter", PlanetaryPositions.GetTropicalJupiterLongitude(birthUtc)),
            ("saturn", "Saturn", PlanetaryPositions.GetTropicalSaturnLongitude(birthUtc)),
            ("rahu", "Rahu", PlanetaryPositions.GetTropicalRahuLongitude(birthUtc)),
            ("ketu", "Ketu", PlanetaryPositions.GetTropicalKetuLongitude(birthUtc))
        };

        foreach (var (lower, cap, trop) in planetLongitudes)
        {
            var sid = VedicCalendar.ToSidereal(trop, birthUtc);
            var sidRashiIdx = VedicCalendar.GetRashiIndex(sid);
            var sidDeg = VedicCalendar.GetDegreeInRashi(sid);

            // Divisional chart signatures — each opens a dimension for corpus retrieval
            var navamsaIdx = VedicCalendar.GetNavamsaRashi(sid);
            signatures.Add($"{lower}_d9_in_{RashiSanskrit[navamsaIdx]}");
            if (navamsaIdx == sidRashiIdx)
                signatures.Add($"{lower}_vargottama");

            var drekkanaIdx = VedicCalendar.GetDrekkanaRashi(sid);
            signatures.Add($"{lower}_d3_in_{RashiSanskrit[drekkanaIdx]}");

            var chaturthamsaIdx = VedicCalendar.GetChaturthamsaRashi(sid);
            signatures.Add($"{lower}_d4_in_{RashiSanskrit[chaturthamsaIdx]}");

            var saptamsaIdx = VedicCalendar.GetSaptamsaRashi(sid);
            signatures.Add($"{lower}_d7_in_{RashiSanskrit[saptamsaIdx]}");

            var dasamsaIdx = VedicCalendar.GetDasamsaRashi(sid);
            signatures.Add($"{lower}_d10_in_{RashiSanskrit[dasamsaIdx]}");

            var dvadasamsaIdx = VedicCalendar.GetDvadasamsaRashi(sid);
            signatures.Add($"{lower}_d12_in_{RashiSanskrit[dvadasamsaIdx]}");

            var shodasamsaIdx = VedicCalendar.GetShodasamsaRashi(sid);
            signatures.Add($"{lower}_d16_in_{RashiSanskrit[shodasamsaIdx]}");

            var vimsamsaIdx = VedicCalendar.GetVimsamsaRashi(sid);
            signatures.Add($"{lower}_d20_in_{RashiSanskrit[vimsamsaIdx]}");

            var chaturvimsamsaIdx = VedicCalendar.GetChaturvimsamsaRashi(sid);
            signatures.Add($"{lower}_d24_in_{RashiSanskrit[chaturvimsamsaIdx]}");

            // Dignity-based signatures
            var dignity = VedicCalendar.GetDignity(cap, sidRashiIdx, sidDeg);
            if (dignity == "deep_exalted" || dignity == "moolatrikona")
                signatures.Add($"{lower}_{dignity}");

            // Retrograde and combust flags
            if (PlanetaryPositions.IsRetrograde(cap, birthUtc))
                signatures.Add($"{lower}_retrograde");
            if (PlanetaryPositions.IsCombust(cap, trop, sunTropical,
                PlanetaryPositions.IsRetrograde(cap, birthUtc)))
                signatures.Add($"{lower}_combust");

            // Planet-in-house placements — requires ascendant
            if (ascSidereal.HasValue)
            {
                var house = VedicCalendar.GetHouse(sid, ascSidereal.Value);
                signatures.Add($"{lower}_in_h{house}");
            }

            // Planet's role for this ascendant — e.g. "saturn_for_lagna_vrishabha"
            // indexes Jataka Chandrika's per-lagna friend/foe classifications.
            if (lagnaRashi is not null)
                signatures.Add($"{lower}_for_lagna_{lagnaRashi}");
        }

        // Current Mahadasha signature — doesn't depend on lagna
        if (now.HasValue)
        {
            var dasha = VedicCalendar.GetCurrentDasha(birthUtc, now.Value);
            signatures.Add($"{dasha.Mahadasha.ToLowerInvariant()}_mahadasha");
        }

        return signatures.ToList();
    }
}
