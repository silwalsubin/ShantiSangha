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
}
