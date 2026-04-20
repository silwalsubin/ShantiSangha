using System.Text.Json.Serialization;

namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// A passage of traditional Vedic interpretation keyed by chart signatures
/// (e.g. "saturn_in_h7", "jupiter_mahadasha"). Loaded from a curated
/// corpus of classical Jyotish sources. Used as invisible context for
/// AI-generated content (reflections, readings, whispers, chat).
/// </summary>
public record JyotishPassage
{
    [JsonPropertyName("id")] public string Id { get; init; } = "";
    [JsonPropertyName("signature_type")] public string SignatureType { get; init; } = "";
    [JsonPropertyName("signatures")] public List<string> Signatures { get; init; } = [];
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    [JsonPropertyName("content")] public string Content { get; init; } = "";
    [JsonPropertyName("themes")] public List<string> Themes { get; init; } = [];
    [JsonPropertyName("polarity")] public string Polarity { get; init; } = "mixed";
    [JsonPropertyName("source")] public string Source { get; init; } = "";
    [JsonPropertyName("scope")] public string Scope { get; init; } = "lifetime";
}

public static class JyotishPassageRotation
{
    /// <summary>
    /// Deterministically selects N passages from the pool, rotating based on
    /// (userId, date) so each day surfaces a different subset for the same
    /// user, and different users see different subsets on the same day.
    /// Used by daily jobs (reflection, portrait, reading) to keep invisible
    /// Vedic context fresh without retrieving a fresh set each run.
    /// </summary>
    public static IReadOnlyList<JyotishPassage> Rotate(
        this IReadOnlyList<JyotishPassage> pool, Guid userId, DateOnly date, int count)
    {
        if (pool.Count <= count) return pool;

        var seed = unchecked(userId.GetHashCode() ^ date.DayNumber.GetHashCode());
        var rng = new Random(seed);
        var indices = Enumerable.Range(0, pool.Count).ToList();
        var chosen = new List<JyotishPassage>(count);
        for (var i = 0; i < count; i++)
        {
            var idx = rng.Next(indices.Count);
            chosen.Add(pool[indices[idx]]);
            indices.RemoveAt(idx);
        }
        return chosen;
    }
}
