using Microsoft.EntityFrameworkCore;
using ShantiSangha.Goals.Data;
using ShantiSangha.Goals.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Goals.Services;

public class PracticeStatusQueryService(GoalsDbContext db) : IPracticeStatusQueryService
{
    public async Task<PracticeStatusSnapshot> GetStatusAsync(
        Guid userId, DateOnly? localDate = null, CancellationToken ct = default)
    {
        var today = localDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var completedDates = await db.GoalCheckIns
            .Where(c => c.Completed
                && db.Goals.Any(g => g.Id == c.GoalId
                    && g.UserId == userId
                    && g.Type == GoalType.Recurring))
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
