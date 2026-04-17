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
        string? transitNote = null;

        if (birth.BirthDate is not null)
        {
            var birthDate = birth.BirthDate.Value;
            var birthHour = 12.0;
            if (birth.BirthTime is not null && TimeOnly.TryParse(birth.BirthTime, out var parsedTime))
                birthHour = parsedTime.Hour + parsedTime.Minute / 60.0;

            var birthDateTime = birthDate.ToDateTime(
                TimeOnly.FromTimeSpan(TimeSpan.FromHours(birthHour)), DateTimeKind.Utc);

            var sunSidereal = VedicCalendar.ToSidereal(
                VedicCalendar.GetTropicalSunLongitude(birthDateTime), birthDateTime);
            sunRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(sunSidereal));

            if (birth.BirthTime is not null)
            {
                var moonSidereal = VedicCalendar.ToSidereal(
                    VedicCalendar.GetTropicalMoonLongitude(birthDateTime), birthDateTime);
                moonRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(moonSidereal));

                var nakshatraIndex = VedicCalendar.GetNakshatraIndex(moonSidereal);
                var (name, quality) = VedicCalendar.GetNakshatra(nakshatraIndex);
                birthNakshatra = $"{name} — associated with {quality}";
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
            TransitNote: transitNote);
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
