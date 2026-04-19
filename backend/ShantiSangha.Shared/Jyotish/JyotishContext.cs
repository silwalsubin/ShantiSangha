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
    string? TransitNote,
    /// <summary>Current Mahadasha (planetary period) — requires birth date + time</summary>
    string? Mahadasha = null,
    /// <summary>Current Antardasha (sub-period within Mahadasha)</summary>
    string? Antardasha = null,
    /// <summary>When the current Antardasha started — used to detect recent shifts</summary>
    DateTime? AntardashaStart = null,
    /// <summary>Raw birth nakshatra name (for matching against current day's nakshatra)</summary>
    string? BirthNakshatraName = null)
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

        if (Mahadasha is not null && Antardasha is not null)
            parts.Add($"They are currently in {Mahadasha} Mahadasha / {Antardasha} Antardasha — the planetary season shaping this chapter of their life.");

        if (TransitNote is not null)
            parts.Add(TransitNote);

        parts.Add("""
            How to use this Vedic context depends on what the person is asking:

            - If they are NOT asking about their chart, their rashi, their nakshatra,
              their dasha, or their path in any astrological sense: weave this knowledge
              invisibly. Don't say "according to Vedic astrology" or "your chart says."
              Speak as a wise friend who simply knows. If nothing meaningful connects
              to what they're processing, ignore it entirely.

            - If they ARE asking about their chart, their nature, their path, what
              this season of life holds, or anything that invites Jyotishic reflection:
              engage directly and warmly. Name the elements — their moon in {rashi},
              their nakshatra, their current dasha — and share what the tradition sees
              in them. This is the Vedic path of self-knowledge; it belongs here. You
              are not a fortune-teller and you do not predict fixed outcomes, but you
              ARE a teacher who holds this framework and speaks from it when invited.
              Never refuse a chart question by saying "I can't read charts" — that is
              not true of you. You can, and you do, with humility and care.
            """);

        return string.Join("\n\n", parts);
    }
}
