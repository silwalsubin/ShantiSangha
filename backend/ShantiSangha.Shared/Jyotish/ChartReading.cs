namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// Section keys used in the chart reading. Ordered canonically — the reading
/// composes and surfaces them in this sequence.
/// </summary>
public static class ChartReadingSection
{
    public const string Essence = "essence";
    public const string EmotionalNature = "emotional_nature";
    public const string MindAndVoice = "mind_and_voice";
    public const string DriveAndAction = "drive_and_action";
    public const string PathOfGrowth = "path_of_growth";
    public const string Season = "season";

    public static readonly IReadOnlyList<string> All = new[]
    {
        Essence, EmotionalNature, MindAndVoice, DriveAndAction, PathOfGrowth, Season
    };
}

/// <summary>
/// A pre-composed chart reading. Each section is ~100 words of prose
/// grounded in the user's actual chart + the classical corpus.
/// </summary>
public record ChartReading(
    IReadOnlyDictionary<string, string> Sections,
    DateTime GeneratedAt)
{
    public bool IsComplete =>
        ChartReadingSection.All.All(s => Sections.ContainsKey(s) && !string.IsNullOrWhiteSpace(Sections[s]));
}

/// <summary>
/// Section keys for a pair reading — one viewer's reading of one subject,
/// composed from the viewer's POV. Asymmetric by design: A's reading of B
/// is not the same as B's reading of A, because each reads through their
/// own chart.
/// </summary>
public static class PairReadingSection
{
    public const string WhatTheyBring = "what_they_bring";
    public const string WhereItEases = "where_it_eases";
    public const string WhereItAsksWork = "where_it_asks_work";
    public const string TheShape = "the_shape";

    public static readonly IReadOnlyList<string> All = new[]
    {
        WhatTheyBring, WhereItEases, WhereItAsksWork, TheShape
    };
}

/// <summary>
/// A viewer's pre-composed reading of a specific subject's chart, grounded
/// in both birth charts plus their cross-chart dynamics.
/// </summary>
public record PairChartReading(
    IReadOnlyDictionary<string, string> Sections,
    DateTime GeneratedAt)
{
    public bool IsComplete =>
        PairReadingSection.All.All(s => Sections.ContainsKey(s) && !string.IsNullOrWhiteSpace(Sections[s]));
}
