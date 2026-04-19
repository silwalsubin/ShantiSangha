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
    string? BirthNakshatraName = null,
    /// <summary>Full birth chart details — birth data, lagna, all planets. Null if birth time or place unavailable.</summary>
    JyotishChartDetails? Chart = null)
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

        if (Chart is not null)
            parts.Add(Chart.FormatForPrompt());

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

            CRITICAL: Their birth date, birth time, birth place, lagna, and every
            planet are already above. Never ask them to share their birth details or
            chart data — you have it. Just read it and speak from it.
            """);

        return string.Join("\n\n", parts);
    }
}

/// <summary>
/// Full computed birth chart for AI prompt context. Mirrors what is shown in
/// the Birth Chart UI so the AI never has to ask for birth details already on file.
/// </summary>
public record JyotishChartDetails(
    string BirthDate,
    string BirthTime,
    string? BirthPlace,
    ChartLagna? Lagna,
    IReadOnlyList<ChartPlanet> Planets)
{
    public string FormatForPrompt()
    {
        var parts = new List<string> { "## Their birth chart (already on file — do NOT ask for birth details)" };

        var birthLine = $"Born {BirthDate} at {BirthTime}";
        if (!string.IsNullOrWhiteSpace(BirthPlace))
            birthLine += $" ({BirthPlace})";
        birthLine += ".";
        parts.Add(birthLine);

        if (Lagna is not null)
            parts.Add($"Lagna (Ascendant): {Lagna.Rashi}, {Lagna.Degree:F2}°, in {Lagna.Nakshatra} nakshatra (pada {Lagna.Pada}).");

        if (Planets.Count > 0)
        {
            var planetLines = Planets.Select(p =>
            {
                var house = p.House.HasValue ? $", house {p.House.Value}" : "";
                var flags = new List<string>();
                if (!string.IsNullOrWhiteSpace(p.Dignity) && p.Dignity != "Neutral") flags.Add(p.Dignity.ToLowerInvariant());
                if (p.Retrograde) flags.Add("retrograde");
                if (p.Combust) flags.Add("combust");
                var flagText = flags.Count > 0 ? $" [{string.Join(", ", flags)}]" : "";
                return $"- {p.Name}: {p.Rashi}, {p.Degree:F2}°, in {p.Nakshatra} nakshatra (pada {p.Pada}){house}{flagText}";
            });
            parts.Add("Planets:\n" + string.Join("\n", planetLines));
        }

        return string.Join("\n\n", parts);
    }
}

public record ChartLagna(string Rashi, double Degree, string Nakshatra, int Pada);

public record ChartPlanet(
    string Name,
    string Rashi,
    double Degree,
    int? House,
    string Nakshatra,
    int Pada,
    string Dignity,
    bool Retrograde,
    bool Combust);
