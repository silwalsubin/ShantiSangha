using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Computes Vedic astrology context for a user on a given date.
/// This context is injected into AI prompts (reflections, chat) invisibly —
/// the user never sees "astrology" in the UI. The AI weaves this awareness
/// naturally into its voice.
/// </summary>
public class JyotishContextService(IProfileQueryService profileQuery) : IJyotishContextService
{
    public async Task<JyotishContext?> GetContextAsync(Guid userId, DateOnly date, CancellationToken ct = default)
    {
        var birth = await profileQuery.GetBirthInfoAsync(userId, ct);
        var today = date.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(6)), DateTimeKind.Utc);

        var (tithi, tithiQuality, vara, varaDeity, yoga, todayNakshatra, todayNakshatraQuality) =
            VedicCalendar.GetPanchang(today);

        string? sunRashi = null;
        string? moonRashi = null;
        string? birthNakshatra = null;
        string? birthNakshatraName = null;
        string? transitNote = null;
        string? mahadasha = null;
        string? antardasha = null;
        DateTime? antardashaStart = null;
        JyotishChartDetails? chartDetails = null;

        if (birth.BirthDate is not null)
        {
            var birthDate = birth.BirthDate.Value;
            var birthTimeOnly = new TimeOnly(12, 0);
            if (birth.BirthTime is not null && TimeOnly.TryParse(birth.BirthTime, out var parsedTime))
                birthTimeOnly = parsedTime;

            // Parse lat/lon from "lat,lon" birth place format
            double? lat = null, lon = null;
            if (!string.IsNullOrWhiteSpace(birth.BirthPlace))
            {
                var parts = birth.BirthPlace.Split(',');
                if (parts.Length == 2
                    && double.TryParse(parts[0].Trim(), System.Globalization.CultureInfo.InvariantCulture, out var parsedLat)
                    && double.TryParse(parts[1].Trim(), System.Globalization.CultureInfo.InvariantCulture, out var parsedLon))
                {
                    lat = parsedLat;
                    lon = parsedLon;
                }
            }

            // Resolve local birth time → UTC via IANA timezone at birth location.
            var birthDateTime = BirthTimeResolver.ResolveBirthUtc(birthDate, birthTimeOnly, lat, lon);

            var sunTropical = VedicCalendar.GetTropicalSunLongitude(birthDateTime);
            var sunSidereal = VedicCalendar.ToSidereal(sunTropical, birthDateTime);
            sunRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(sunSidereal));

            if (birth.BirthTime is not null)
            {
                var moonSidereal = VedicCalendar.ToSidereal(
                    VedicCalendar.GetTropicalMoonLongitude(birthDateTime), birthDateTime);
                moonRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(moonSidereal));

                var nakshatraIndex = VedicCalendar.GetNakshatraIndex(moonSidereal);
                var (name, quality) = VedicCalendar.GetNakshatra(nakshatraIndex);
                birthNakshatraName = name;
                birthNakshatra = $"{name} — associated with {quality}";

                // Vimshottari dasha requires birth time
                var dasha = VedicCalendar.GetCurrentDasha(birthDateTime, today);
                mahadasha = dasha.Mahadasha;
                antardasha = dasha.Antardasha;
                antardashaStart = dasha.AntardashaStart;

                chartDetails = BuildChartDetails(birth, birthDateTime, sunTropical, lat, lon);
            }

            transitNote = GenerateTransitNote(sunRashi, todayNakshatra, todayNakshatraQuality, tithi);
        }

        var panchangParts = new List<string>
        {
            $"Today is {vara} ({varaDeity})",
            $"Tithi: {tithi} — a day for {tithiQuality}",
            $"Moon nakshatra: {todayNakshatra} — {todayNakshatraQuality}",
            $"Yoga: {yoga}"
        };
        var panchangSummary = string.Join(". ", panchangParts) + ".";

        return new JyotishContext(
            SunRashi: sunRashi,
            MoonRashi: moonRashi,
            BirthNakshatra: birthNakshatra,
            CurrentNakshatra: todayNakshatra,
            Tithi: tithi,
            Vara: vara,
            Yoga: yoga,
            PanchangSummary: panchangSummary,
            TransitNote: transitNote,
            Mahadasha: mahadasha,
            Antardasha: antardasha,
            AntardashaStart: antardashaStart,
            BirthNakshatraName: birthNakshatraName,
            Chart: chartDetails);
    }

    private static JyotishChartDetails BuildChartDetails(
        UserBirthInfo birth,
        DateTime birthDateTime,
        double sunTropical,
        double? lat,
        double? lon)
    {
        ChartLagna? lagnaDetails = null;
        double? ascendantSidereal = null;
        if (lat.HasValue && lon.HasValue)
        {
            var ascTropical = VedicCalendar.GetTropicalAscendant(birthDateTime, lat.Value, lon.Value);
            var ascSidereal = VedicCalendar.ToSidereal(ascTropical, birthDateTime);
            ascendantSidereal = ascSidereal;
            var ascRashiIdx = VedicCalendar.GetRashiIndex(ascSidereal);
            var ascNakIdx = VedicCalendar.GetNakshatraIndex(ascSidereal);
            var (ascNakName, _) = VedicCalendar.GetNakshatra(ascNakIdx);
            lagnaDetails = new ChartLagna(
                Rashi: VedicCalendar.GetRashi(ascRashiIdx),
                Degree: Math.Round(VedicCalendar.GetDegreeInRashi(ascSidereal), 2),
                Nakshatra: ascNakName,
                Pada: VedicCalendar.GetPada(ascSidereal));
        }

        var planetLongitudes = new (string Name, double Tropical)[]
        {
            ("Sun", sunTropical),
            ("Moon", VedicCalendar.GetTropicalMoonLongitude(birthDateTime)),
            ("Mercury", PlanetaryPositions.GetTropicalMercuryLongitude(birthDateTime)),
            ("Venus", PlanetaryPositions.GetTropicalVenusLongitude(birthDateTime)),
            ("Mars", PlanetaryPositions.GetTropicalMarsLongitude(birthDateTime)),
            ("Jupiter", PlanetaryPositions.GetTropicalJupiterLongitude(birthDateTime)),
            ("Saturn", PlanetaryPositions.GetTropicalSaturnLongitude(birthDateTime)),
            ("Rahu", PlanetaryPositions.GetTropicalRahuLongitude(birthDateTime)),
            ("Ketu", PlanetaryPositions.GetTropicalKetuLongitude(birthDateTime))
        };

        var planets = planetLongitudes.Select(p =>
        {
            var sidereal = VedicCalendar.ToSidereal(p.Tropical, birthDateTime);
            var rashiIdx = VedicCalendar.GetRashiIndex(sidereal);
            var degInRashi = VedicCalendar.GetDegreeInRashi(sidereal);
            var nakIdx = VedicCalendar.GetNakshatraIndex(sidereal);
            var (nakName, _) = VedicCalendar.GetNakshatra(nakIdx);
            int? house = ascendantSidereal.HasValue
                ? VedicCalendar.GetHouse(sidereal, ascendantSidereal.Value)
                : null;
            var retrograde = PlanetaryPositions.IsRetrograde(p.Name, birthDateTime);
            return new ChartPlanet(
                Name: p.Name,
                Rashi: VedicCalendar.GetRashi(rashiIdx),
                Degree: Math.Round(degInRashi, 2),
                House: house,
                Nakshatra: nakName,
                Pada: VedicCalendar.GetPada(sidereal),
                Dignity: VedicCalendar.GetDignity(p.Name, rashiIdx, degInRashi),
                Retrograde: retrograde,
                Combust: PlanetaryPositions.IsCombust(p.Name, p.Tropical, sunTropical, retrograde));
        }).ToList();

        return new JyotishChartDetails(
            BirthDate: birth.BirthDate!.Value.ToString("MMMM d, yyyy"),
            BirthTime: birth.BirthTime ?? "unknown",
            BirthPlace: birth.BirthPlace,
            Lagna: lagnaDetails,
            Planets: planets);
    }

    private static string? GenerateTransitNote(
        string? sunRashi, string todayNakshatra, string todayNakshatraQuality, string tithi)
    {
        if (sunRashi is null) return null;

        if (tithi.Contains("Ekadashi"))
            return $"Today is Ekadashi — traditionally a day of fasting, inner focus, and heightened spiritual receptivity. The moon in {todayNakshatra} adds a quality of {todayNakshatraQuality}.";
        if (tithi.Contains("Purnima"))
            return $"Full moon today. The moon in {todayNakshatra} brings {todayNakshatraQuality}. For someone born under {sunRashi}, this is a day of culmination and clarity.";
        if (tithi.Contains("Amavasya"))
            return $"New moon today. A day of stillness and turning inward. The {todayNakshatra} nakshatra emphasizes {todayNakshatraQuality}.";

        return $"Today's moon passes through {todayNakshatra}, carrying the energy of {todayNakshatraQuality}. For someone born under {sunRashi}, this is part of an ongoing rhythm.";
    }

}
