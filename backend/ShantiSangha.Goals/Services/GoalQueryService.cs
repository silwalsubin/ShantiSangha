using Microsoft.EntityFrameworkCore;
using ShantiSangha.Goals.Data;
using ShantiSangha.Goals.Models;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Goals.Services;

public class GoalQueryService(GoalsDbContext db) : IGoalQueryService
{
    public async Task<IReadOnlyList<GoalSummaryDto>> GetActiveGoalsForContextAsync(
        Guid userId, CancellationToken ct = default)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        var goals = await db.Goals
            .Where(g => g.UserId == userId && g.ArchivedAt == null)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync(ct);

        return goals.Select(g =>
        {
            var (currentStreak, longestStreak) = GoalService.ComputeStreaks(g.CheckIns, today);
            var checkedInToday = g.Type == GoalType.Recurring
                ? g.CheckIns.Any(c => c.Date == today && c.Completed)
                : (bool?)null;
            var daysRemaining = g.Type == GoalType.OneTime && g.TargetDate.HasValue
                ? g.TargetDate.Value.DayNumber - today.DayNumber
                : (int?)null;

            return new GoalSummaryDto(
                g.Title,
                g.Type.ToString(),
                currentStreak,
                longestStreak,
                checkedInToday,
                daysRemaining,
                g.CompletedAt.HasValue,
                g.Progress,
                g.DeeperWhy);
        }).ToList();
    }
}
