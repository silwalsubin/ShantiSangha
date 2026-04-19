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
