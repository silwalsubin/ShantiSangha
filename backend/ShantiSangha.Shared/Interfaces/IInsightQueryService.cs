namespace ShantiSangha.Shared.Interfaces;

public interface IInsightQueryService
{
    Task<IReadOnlyList<string>> GetRecentInsightsAsync(Guid userId, int count = 5, CancellationToken ct = default);
    Task<IReadOnlyList<string>> SearchInsightsAsync(Guid userId, string query, int count = 5, CancellationToken ct = default);
}
