namespace ShantiSangha.Shared;

/// <summary>
/// Per-surface model routing. Registered with Semantic Kernel under these
/// service keys so callers resolve the right model via
/// <c>kernel.GetRequiredService&lt;IChatCompletionService&gt;(AiModels.Fast)</c>.
///
/// Keep the number of tiers small. Smart = synthesis quality matters (chart
/// reading, chart chat). Fast = short stylistic output where a larger model
/// would be ~15× more expensive for no measurable quality win (titles,
/// summaries, short reflections, journal prompts).
/// </summary>
public static class AiModels
{
    public const string SmartServiceId = "smart";
    public const string FastServiceId = "fast";

    public const string SmartModel = "gpt-4o";
    public const string FastModel = "gpt-4o-mini";
}
