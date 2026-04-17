namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// Vedic astrology context for a user on a given day.
/// This is consumed by AI prompts — never shown directly in UI.
/// </summary>
public record JyotishContext(
    /// <summary>Sidereal sun sign (Mesha, Vrishabha, etc.)</summary>
    string? SunRashi,
    /// <summary>Sidereal moon sign (if birth time is known)</summary>
    string? MoonRashi,
    /// <summary>Birth nakshatra (lunar mansion, if birth time is known)</summary>
    string? BirthNakshatra,
    /// <summary>Current moon nakshatra for today</summary>
    string CurrentNakshatra,
    /// <summary>Today's tithi (lunar day)</summary>
    string Tithi,
    /// <summary>Today's Vedic weekday (Vara)</summary>
    string Vara,
    /// <summary>Yoga for today</summary>
    string Yoga,
    /// <summary>Brief panchang note for AI context</summary>
    string PanchangSummary,
    /// <summary>Any notable transit or period context</summary>
    string? TransitNote)
{
    /// <summary>
    /// Formats this context as a text block for AI prompt injection.
    /// </summary>
    public string FormatForPrompt()
    {
        var parts = new List<string>
        {
            "## Vedic Context (invisible — weave naturally, never label as astrology)"
        };

        parts.Add(PanchangSummary);

        if (MoonRashi is not null)
            parts.Add($"Their Vedic rashi (moon sign — the primary identifier in Jyotish): {MoonRashi}.");
        else if (SunRashi is not null)
            parts.Add($"Their sun sign (approximate — birth time unknown): {SunRashi}.");

        if (BirthNakshatra is not null)
            parts.Add($"Their birth nakshatra: {BirthNakshatra}.");

        if (TransitNote is not null)
            parts.Add(TransitNote);

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
