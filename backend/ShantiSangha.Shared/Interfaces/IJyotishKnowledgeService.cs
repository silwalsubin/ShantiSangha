using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Serves passages from the curated Jyotish knowledge corpus. Supports two
/// retrieval modes: exact signature match (for chart-specific facts) and
/// semantic search (for thematic composition).
/// </summary>
public interface IJyotishKnowledgeService
{
    /// <summary>
    /// Exact-match retrieval by signature string (e.g. "saturn_in_h7").
    /// Returns all passages whose signatures[] array contains any of the
    /// inputs, deduplicated by passage id.
    /// </summary>
    Task<IReadOnlyList<JyotishPassage>> GetPassagesAsync(
        IEnumerable<string> signatures,
        CancellationToken ct = default);

    /// <summary>
    /// Semantic retrieval by free-text query. Optional signature_type
    /// filter narrows the search to one category. Returns top-K by L2
    /// distance on the 1536-dim embedding.
    /// </summary>
    Task<IReadOnlyList<JyotishPassage>> SearchSemanticAsync(
        string query,
        string? signatureType = null,
        int topK = 10,
        CancellationToken ct = default);

    /// <summary>Total passages in the corpus (diagnostic).</summary>
    Task<int> CountAsync(CancellationToken ct = default);

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
