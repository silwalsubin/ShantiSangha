using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// Computes Vedic astrology context for a user on a given date.
/// This context is injected into AI prompts (reflections, chat) invisibly —
/// the user never sees "astrology" in the UI. The AI weaves this awareness
/// naturally into its voice.
/// </summary>
public class JyotishContextService(IProfileQueryService profileQuery)
{
    /// <summary>
    /// Build the full Jyotish context for a user on a given date.
    /// Returns null if the user has no birth data at all.
    /// </summary>
    public async Task<JyotishContext?> GetContextAsync(Guid userId, DateOnly date, CancellationToken ct = default)
    {
        var birth = await profileQuery.GetBirthInfoAsync(userId, ct);
        var today = date.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(6)), DateTimeKind.Utc); // 6 AM approx

        // Panchang is available for everyone (it's about today, not birth)
        var (tithi, tithiQuality, vara, varaDeity, yoga, todayNakshatra, todayNakshatraQuality) =
            VedicCalendar.GetPanchang(today);

        string? sunRashi = null;
        string? moonRashi = null;
        string? birthNakshatra = null;
        string? transitNote = null;

        if (birth.BirthDate is not null)
        {
            var birthDate = birth.BirthDate.Value;

            // Parse birth time if available, otherwise use noon
            var birthHour = 12.0;
            if (birth.BirthTime is not null && TimeOnly.TryParse(birth.BirthTime, out var parsedTime))
            {
                birthHour = parsedTime.Hour + parsedTime.Minute / 60.0;
            }

            var birthDateTime = birthDate.ToDateTime(
                TimeOnly.FromTimeSpan(TimeSpan.FromHours(birthHour)), DateTimeKind.Utc);

            // Sun rashi (sidereal sun sign at birth)
            var sunSidereal = VedicCalendar.ToSidereal(
                VedicCalendar.GetTropicalSunLongitude(birthDateTime), birthDateTime);
            sunRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(sunSidereal));

            // Moon rashi and birth nakshatra (only meaningful with birth time)
            if (birth.BirthTime is not null)
            {
                var moonSidereal = VedicCalendar.ToSidereal(
                    VedicCalendar.GetTropicalMoonLongitude(birthDateTime), birthDateTime);
                moonRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(moonSidereal));

                var nakshatraIndex = VedicCalendar.GetNakshatraIndex(moonSidereal);
                var (name, quality) = VedicCalendar.GetNakshatra(nakshatraIndex);
                birthNakshatra = $"{name} — associated with {quality}";
            }

            // Generate a transit note based on today's moon nakshatra relative to birth
            transitNote = GenerateTransitNote(sunRashi, todayNakshatra, todayNakshatraQuality, tithi);
        }

        // Build panchang summary
        var panchangParts = new List<string>
        {
            $"Today is {vara} ({varaDeity})",
            $"Tithi: {tithi} — a day for {tithiQuality}",
            $"Moon nakshatra: {todayNakshatra} — {todayNakshatraQuality}",
            $"Yoga: {yoga}"
        };
        var panchangSummary = string.Join(". ", panchangParts) + ".";

        // Only return null if we have absolutely nothing (no birth data AND somehow panchang failed)
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

    /// <summary>
    /// Generates a brief, AI-digestible transit note connecting today's sky to the user's chart.
    /// </summary>
    private static string? GenerateTransitNote(
        string? sunRashi, string todayNakshatra, string todayNakshatraQuality, string tithi)
    {
        if (sunRashi is null) return null;

        // Special tithi notes
        if (tithi.Contains("Ekadashi"))
            return $"Today is Ekadashi — traditionally a day of fasting, inner focus, and heightened spiritual receptivity. The moon in {todayNakshatra} adds a quality of {todayNakshatraQuality}.";

        if (tithi.Contains("Purnima"))
            return $"Full moon today. The moon in {todayNakshatra} brings {todayNakshatraQuality}. For someone born under {sunRashi}, this is a day of culmination and clarity.";

        if (tithi.Contains("Amavasya"))
            return $"New moon today. A day of stillness and turning inward. The {todayNakshatra} nakshatra emphasizes {todayNakshatraQuality}.";

        return $"Today's moon passes through {todayNakshatra}, carrying the energy of {todayNakshatraQuality}. For someone born under {sunRashi}, this is part of an ongoing rhythm.";
    }

    /// <summary>
    /// Formats the Jyotish context as a text block for AI prompt injection.
    /// This is what gets appended to reflection and chat system prompts.
    /// </summary>
    public static string FormatForPrompt(JyotishContext ctx)
    {
        var parts = new List<string>
        {
            "## Vedic Context (invisible — weave naturally, never label as astrology)"
        };

        parts.Add(ctx.PanchangSummary);

        if (ctx.SunRashi is not null)
            parts.Add($"Their birth sun sign (rashi): {ctx.SunRashi}.");

        if (ctx.MoonRashi is not null)
            parts.Add($"Their birth moon sign: {ctx.MoonRashi}.");

        if (ctx.BirthNakshatra is not null)
            parts.Add($"Their birth nakshatra: {ctx.BirthNakshatra}.");

        if (ctx.TransitNote is not null)
            parts.Add(ctx.TransitNote);

        parts.Add("""
            Use this context to enrich your observations — but NEVER say "according to
            Vedic astrology" or "your chart says." Speak with this knowledge the way a
            wise friend would: naturally, as if you simply know. The user should feel
            the depth without seeing the source. If the Vedic context doesn't connect
            to anything meaningful about their practice today, ignore it entirely.
            """);

        return string.Join("\n\n", parts);
    }
}
