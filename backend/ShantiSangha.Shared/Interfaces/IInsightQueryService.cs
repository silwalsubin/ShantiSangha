using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IInsightQueryService
{
    Task<IReadOnlyList<string>> GetRecentInsightsAsync(Guid userId, int count = 5, CancellationToken ct = default);
    Task<IReadOnlyList<string>> SearchInsightsAsync(Guid userId, string query, int count = 5, CancellationToken ct = default);

    /// <summary>
    /// Semantic search across insights AND journals — returns the most relevant
    /// past entries for a given query. Used by the reflection job to find
    /// thematically relevant context for callbacks and seed-planting.
    /// </summary>
    Task<IReadOnlyList<SemanticSearchResultDto>> SearchAllAsync(Guid userId, string query, int topK = 5, CancellationToken ct = default);

    /// <summary>
    /// Check if a new insight is semantically similar to existing insights.
    /// Returns true if a similar insight already exists (distance below threshold).
    /// Used to prevent duplicate insights that are worded differently.
    /// </summary>
    Task<bool> IsSimilarInsightExistsAsync(Guid userId, string content, CancellationToken ct = default);
}
