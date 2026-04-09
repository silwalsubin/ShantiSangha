using Microsoft.EntityFrameworkCore;
using ShantiSangha.Insights.Data;
using ShantiSangha.Insights.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Insights.Services;

public class SummaryQueryService(InsightsDbContext db) : ISummaryQueryService
{
    public async Task<IReadOnlyList<string>> GetRecentSummariesAsync(
        Guid userId, int count = 3, CancellationToken ct = default)
    {
        return await db.Summaries
            .Where(s => s.UserId == userId && s.SourceType == SummarySourceType.Conversation)
            .OrderByDescending(s => s.CreatedAt)
            .Take(count)
            .Select(s => s.Content)
            .ToListAsync(ct);
    }
}
