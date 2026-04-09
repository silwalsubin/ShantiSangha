using Microsoft.EntityFrameworkCore;
using ShantiSangha.Insights.Contracts;
using ShantiSangha.Insights.Data;

namespace ShantiSangha.Insights.Services;

public class InsightService(InsightsDbContext db)
{
    public async Task<IReadOnlyList<InsightDto>> ListInsightsAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        pageSize = Math.Clamp(pageSize, 1, 50);

        return await db.SavedInsights
            .Where(i => i.UserId == userId)
            .OrderByDescending(i => i.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(i => new InsightDto(i.Id, i.Content, i.SourceConversationId, i.SourceJournalId, i.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<bool> DeleteInsightAsync(Guid id, Guid userId, CancellationToken ct = default)
    {
        var insight = await db.SavedInsights
            .FirstOrDefaultAsync(i => i.Id == id && i.UserId == userId, ct);

        if (insight is null) return false;

        db.SavedInsights.Remove(insight);
        await db.SaveChangesAsync(ct);
        return true;
    }
}
