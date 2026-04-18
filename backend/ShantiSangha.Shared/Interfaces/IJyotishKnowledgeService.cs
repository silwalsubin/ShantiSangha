using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Serves passages from the curated Jyotish knowledge corpus, keyed by
/// chart signatures. Used as invisible context for AI-generated content.
/// </summary>
public interface IJyotishKnowledgeService
{
    /// <summary>Returns all passages matching any of the given signatures.</summary>
    IReadOnlyList<JyotishPassage> GetPassages(IEnumerable<string> signatures);

    /// <summary>Total passages loaded (diagnostic).</summary>
    int TotalPassages { get; }

    /// <summary>
    /// Given birth data and an optional current date, returns the chart
    /// signatures that apply to the user (for later retrieval). Returns
    /// an empty list if birth time is missing.
    /// </summary>
    IReadOnlyList<string> ComputeSignaturesForBirth(
        DateOnly birthDate,
        TimeOnly? birthTime,
        double? latitude,
        double? longitude,
        DateTime? now = null);
}
