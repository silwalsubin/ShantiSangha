namespace ShantiSangha.Practices.Models;

/// <summary>
/// Cached AI-generated reflection for a Journey date range.
/// Keyed by (UserId, FromDate, ToDate) + InputHash so any change
/// in the underlying check-in data invalidates the cache.
/// </summary>
public class JourneyReflection
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly FromDate { get; set; }
    public DateOnly ToDate { get; set; }
    public string Content { get; set; } = string.Empty;
    /// <summary>Hash of the input context (check-in counts, completions, titles) — regenerate on mismatch.</summary>
    public string InputHash { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
