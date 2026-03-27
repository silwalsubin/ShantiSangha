namespace ShantiSangha.Core.Services;

public record SemanticSearchResult(
    Guid Id,
    string Type,       // "insight" | "journal" | "message"
    string Content,
    double Distance,
    DateTime CreatedAt);

public interface ISemanticSearchService
{
    Task<IReadOnlyList<SemanticSearchResult>> SearchInsightsAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default);

    Task<IReadOnlyList<SemanticSearchResult>> SearchJournalsAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default);

    Task<IReadOnlyList<SemanticSearchResult>> SearchAllAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default);
}
