using Microsoft.EntityFrameworkCore;
using ShantiSangha.Practices.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Practices.Services;

public class PracticeStatusQueryService(PracticesDbContext db) : IPracticeStatusQueryService
{
    public async Task<PracticeStatusSnapshot> GetStatusAsync(
        Guid userId, DateOnly? localDate = null, CancellationToken ct = default)
    {
        var today = localDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var completedDates = await db.PracticeCheckIns
            .Where(c => c.Completed
                && db.Practices.Any(p => p.Id == c.PracticeId && p.UserId == userId))
            .Select(c => c.Date)
            .Distinct()
            .ToListAsync(ct);

        if (completedDates.Count == 0)
            return new PracticeStatusSnapshot(false, 0, null);

        var dateSet = completedDates.ToHashSet();
        var checkedInToday = dateSet.Contains(today);

        var currentStreak = 0;
        var cursor = checkedInToday ? today : today.AddDays(-1);
        while (dateSet.Contains(cursor))
        {
            currentStreak++;
            cursor = cursor.AddDays(-1);
        }

        var lastActive = completedDates.Max();

        return new PracticeStatusSnapshot(checkedInToday, currentStreak, lastActive);
    }
}
