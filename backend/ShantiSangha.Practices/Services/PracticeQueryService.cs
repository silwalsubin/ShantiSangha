using Microsoft.EntityFrameworkCore;
using ShantiSangha.Practices.Data;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Practices.Services;

public class PracticeQueryService(PracticesDbContext db) : IPracticeQueryService
{
    public async Task<IReadOnlyList<PracticeSummaryDto>> GetActivePracticesForContextAsync(
        Guid userId, DateOnly? localDate = null, CancellationToken ct = default)
    {
        var today = localDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var practices = await db.Practices
            .Where(p => p.UserId == userId && p.ArchivedAt == null)
            .Include(p => p.CheckIns)
            .OrderBy(p => p.CreatedAt)
            .ToListAsync(ct);

        return practices.Select(p =>
        {
            var (currentStreak, longestStreak) = PracticeService.ComputeStreaks(p.CheckIns, today);
            var checkedInToday = p.CheckIns.Any(c => c.Date == today && c.Completed);

            return new PracticeSummaryDto(
                p.Title,
                currentStreak,
                longestStreak,
                checkedInToday,
                p.DeeperWhy);
        }).ToList();
    }
}
