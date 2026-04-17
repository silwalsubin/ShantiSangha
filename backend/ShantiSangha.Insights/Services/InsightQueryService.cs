using Microsoft.EntityFrameworkCore;
using ShantiSangha.Insights.Data;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Insights.Services;

public class InsightQueryService(
    InsightsDbContext db,
    SemanticSearchService searchService) : IInsightQueryService
{
    public async Task<IReadOnlyList<string>> GetRecentInsightsAsync(
        Guid userId, int count = 5, CancellationToken ct = default)
    {
        return await db.SavedInsights
            .Where(i => i.UserId == userId)
            .OrderByDescending(i => i.CreatedAt)
            .Take(count)
            .Select(i => i.Content)
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<string>> SearchInsightsAsync(
        Guid userId, string query, int count = 5, CancellationToken ct = default)
    {
        var results = await searchService.SearchInsightsAsync(userId, query, count, ct);
        return results.Select(r => r.Content).ToList();
    }

    public async Task<IReadOnlyList<SemanticSearchResultDto>> SearchAllAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        return await searchService.SearchAllAsync(userId, query, topK, ct);
    }

    public async Task<bool> IsSimilarInsightExistsAsync(
        Guid userId, string content, CancellationToken ct = default)
    {
        var results = await searchService.SearchInsightsAsync(userId, content, 1, ct);
        // L2 distance threshold — below 0.3 means very similar content
        return results.Count > 0 && results[0].Distance < 0.3;
    }
}
