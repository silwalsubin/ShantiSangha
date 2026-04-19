namespace ShantiSangha.Jyotish.Models;

/// <summary>
/// Pre-composed, source-grounded reading of a user's birth chart. Generated
/// once per unique chart (hash of birth date + time + place); regenerated
/// when those change. Chat conversations read from this rather than
/// composing prose from raw chart + corpus on every turn.
/// </summary>
public class ChartReadingEntity
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>
    /// SHA-256 of normalized birth details. Any change invalidates the reading;
    /// the next GET regenerates from the new chart.
    /// </summary>
    public string ChartHash { get; set; } = string.Empty;

    /// <summary>
    /// JSON object keyed by section name (essence, emotional_nature,
    /// mind_and_voice, drive_and_action, path_of_growth, season).
    /// Values are the composed prose strings. Missing keys mean that
    /// section failed composition and should be retried.
    /// </summary>
    public string SectionsJson { get; set; } = "{}";

    /// <summary>
    /// JSON map of section → array of passage ids that informed it.
    /// Used for audit and future "show your work" UX.
    /// </summary>
    public string PassageUsageJson { get; set; } = "{}";

    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
