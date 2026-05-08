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
    JyotishChartDetails? Chart = null,
    /// <summary>Tara bala — today's position in the 9-tara cycle counted from birth nakshatra. Null if birth time isn't known.</summary>
    TaraBala? TaraBala = null)
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

        if (TaraBala is not null)
            parts.Add(
                $"Tara bala today: position {TaraBala.Position} of 27 from janma — " +
                $"{TaraBala.Name} ({TaraBala.Polarity}). The moon's daily journey from " +
                $"their birth {TaraBala.FromNakshatra} to today's {TaraBala.ToNakshatra} " +
                $"sits in this slot of the 9-tara cycle.");

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

/// <summary>
/// Tara bala — the lunar-day quality cycle counted from the person's birth
/// nakshatra. Position 1..27 is the absolute count from janma; Number 1..9
/// is the position within the 9-tara cycle (Janma, Sampat, Vipat, Kshema,
/// Pratyak, Sadhaka, Vadha, Mitra, Atimitra), which repeats three times
/// across the 27 nakshatras. Polarity reduces to favorable / warning /
/// neutral so the AI doesn't have to interpret the technical name.
/// </summary>
public record TaraBala(
    int Position,
    int Number,
    string Name,
    string Polarity,
    string FromNakshatra,
    string ToNakshatra);

public static class JyotishSignatureDerivation
{
    /// <summary>
    /// Derives corpus signature strings from a populated birth chart.
    /// These are the same shape as signatures produced by the chart engine
    /// so signature-based corpus lookup hits the right passages.
    /// </summary>
    public static IEnumerable<string> DeriveSignatures(this JyotishChartDetails chart)
    {
        var sigs = new List<string>();

        var lagnaRashi = chart.Lagna is not null
            ? ExtractSanskrit(chart.Lagna.Rashi).ToLowerInvariant()
            : null;

        if (lagnaRashi is not null)
            sigs.Add($"lagna_in_{lagnaRashi}");

        foreach (var p in chart.Planets)
        {
            var planet = p.Name.ToLowerInvariant();
            var rashi = ExtractSanskrit(p.Rashi).ToLowerInvariant();

            sigs.Add($"{planet}_in_{rashi}");

            if (p.House.HasValue)
            {
                sigs.Add($"{planet}_in_h{p.House.Value}");
                // Compound (planet in house with specific ascendant) — only
                // ingested today for 1st-house variants but harmless otherwise.
                if (lagnaRashi is not null)
                    sigs.Add($"{planet}_in_h{p.House.Value}__lagna_{lagnaRashi}");

                // Mangal dosha (Manglik): Mars in 1st, 2nd, 4th, 7th, 8th, or 12th
                // from Lagna. Internal signature only — never surfaced as a UI
                // label. Lets chart chat + RAG answer "am I Manglik?" with grounded
                // context rather than relying on the model's training knowledge.
                if (planet == "mars" && p.House.Value is 1 or 2 or 4 or 7 or 8 or 12)
                    sigs.Add("manglik");
            }

            // Planet's role for this ascendant — e.g. "jupiter_for_lagna_mesha"
            // indexes Jataka Chandrika's per-lagna friend/foe classifications.
            if (lagnaRashi is not null)
                sigs.Add($"{planet}_for_lagna_{lagnaRashi}");
        }

        // Two-planet conjunctions (any two planets sharing a sign)
        var byRashi = chart.Planets
            .GroupBy(p => ExtractSanskrit(p.Rashi).ToLowerInvariant())
            .Where(g => g.Count() >= 2);
        foreach (var group in byRashi)
        {
            var names = group.Select(p => p.Name.ToLowerInvariant()).OrderBy(n => n, StringComparer.Ordinal).ToList();
            for (int i = 0; i < names.Count; i++)
                for (int j = i + 1; j < names.Count; j++)
                    sigs.Add($"conj_{names[i]}_{names[j]}");
        }

        // Moon's nakshatra — the nakshatra passages in the corpus are keyed
        // as moon_in_{nakshatra}.
        var moon = chart.Planets.FirstOrDefault(p => p.Name == "Moon");
        if (moon is not null)
            sigs.Add($"moon_in_{NormalizeNakshatra(moon.Nakshatra)}");

        return sigs;
    }

    /// <summary>
    /// Derives signatures from the full context (chart + current dasha).
    /// </summary>
    public static IEnumerable<string> DeriveSignatures(this JyotishContext ctx)
    {
        var sigs = new List<string>();
        if (ctx.Chart is not null)
            sigs.AddRange(ctx.Chart.DeriveSignatures());
        if (!string.IsNullOrWhiteSpace(ctx.Mahadasha))
        {
            var mahadashaPlanet = ctx.Mahadasha.ToLowerInvariant();
            sigs.Add($"{mahadashaPlanet}_mahadasha");

            // Mahadasha + Antardasha pair (e.g. jupiter_md_moon_ad). The corpus
            // carries 81 dasha-pair phalas from Phaladeepika; without this
            // emission, the pair passages are never reachable from a chart
            // reading and the active short-period influence is invisible.
            if (!string.IsNullOrWhiteSpace(ctx.Antardasha))
            {
                var antardashaPlanet = ctx.Antardasha.ToLowerInvariant();
                sigs.Add($"{mahadashaPlanet}_md_{antardashaPlanet}_ad");
            }

            // Bhava-lord dasha signatures: for each house whose lord is the
            // current mahadasha planet, emit dasha_of_lord_of_h{N}.
            if (ctx.Chart?.Lagna is not null)
            {
                var lagnaRashi = ExtractSanskrit(ctx.Chart.Lagna.Rashi).ToLowerInvariant();
                if (RashiIndex.TryGetValue(lagnaRashi, out var lagnaIdx))
                {
                    for (int house = 1; house <= 12; house++)
                    {
                        var signIdx = (lagnaIdx + house - 1) % 12;
                        if (string.Equals(RashiLord[signIdx], mahadashaPlanet, StringComparison.Ordinal))
                            sigs.Add($"dasha_of_lord_of_h{house}");
                    }
                }
            }
        }
        return sigs;
    }

    private static readonly Dictionary<string, int> RashiIndex = new(StringComparer.Ordinal)
    {
        ["mesha"] = 0, ["vrishabha"] = 1, ["mithuna"] = 2, ["karka"] = 3, ["kataka"] = 3,
        ["simha"] = 4, ["kanya"] = 5, ["tula"] = 6, ["thula"] = 6, ["vrischika"] = 7, ["vrishchika"] = 7,
        ["dhanu"] = 8, ["dhanus"] = 8, ["makara"] = 9, ["kumbha"] = 10, ["meena"] = 11,
    };

    private static readonly string[] RashiLord =
    [
        "mars", "venus", "mercury", "moon", "sun", "mercury",
        "venus", "mars", "jupiter", "saturn", "saturn", "jupiter"
    ];

    /// <summary>"Mesha (Aries)" → "Mesha". Handles labels that already have no paren.</summary>
    private static string ExtractSanskrit(string rashiLabel)
    {
        var paren = rashiLabel.IndexOf('(');
        return (paren > 0 ? rashiLabel[..paren] : rashiLabel).Trim();
    }

    /// <summary>
    /// Nakshatra signature normalization — strip spaces, dots, and lowercase.
    /// "Purva Phalguni" → "purvaphalguni"; matches the corpus's alias spellings.
    /// </summary>
    private static string NormalizeNakshatra(string name)
        => name.Replace(" ", "").Replace(".", "").Replace("_", "").ToLowerInvariant();
}

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
