using Microsoft.EntityFrameworkCore;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;

namespace ShantiSangha.Wellness.Services;

public class ReflectionQueryService(WellnessDbContext db) : IReflectionQueryService
{
    public async Task<string?> GetRecentReflectionAsync(Guid userId, CancellationToken ct = default)
    {
        var cutoff = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-2);

        var reflection = await db.DailyReflections
            .Where(r => r.UserId == userId && r.Date >= cutoff)
            .OrderByDescending(r => r.Date)
            .Select(r => r.Content)
            .FirstOrDefaultAsync(ct);

        return reflection;
    }
}
