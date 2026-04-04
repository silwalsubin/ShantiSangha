using Microsoft.EntityFrameworkCore;
using ShantiSangha.Api.Services;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class GoalRoutes
{
    public static void MapGoalRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/goals").RequireAuthorization();

        group.MapPost("/", CreateGoal);
        group.MapGet("/", ListGoals);
        group.MapGet("/today", GetToday);
        group.MapGet("/{id:guid}", GetGoal);
        group.MapPatch("/{id:guid}", UpdateGoal);
        group.MapDelete("/{id:guid}", DeleteGoal);
        group.MapPost("/{id:guid}/checkin", CheckIn);
        group.MapDelete("/{id:guid}/checkin", UndoCheckIn);
        group.MapGet("/{id:guid}/history", GetHistory);
    }

    private static async Task<IResult> CreateGoal(
        ICurrentUser currentUser, AppDbContext db, CreateGoalRequest body)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        if (string.IsNullOrWhiteSpace(body.Title))
            return Results.BadRequest(new { error = "Title is required." });

        DateOnly? targetDate = null;
        if (body.TargetDate is not null && DateOnly.TryParse(body.TargetDate, out var parsed))
            targetDate = parsed;

        var goal = new Goal
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Title = body.Title.Trim(),
            Type = body.Type,
            Frequency = body.Frequency,
            FrequencyTarget = body.FrequencyTarget,
            TargetDate = targetDate,
            DeeperWhy = body.DeeperWhy?.Trim(),
            CreatedAt = DateTime.UtcNow
        };

        db.Goals.Add(goal);

        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Results.Conflict(new { error = "A goal with that title already exists." });
        }

        return Results.Created($"/goals/{goal.Id}", new
        {
            goal.Id, goal.Title, goal.Type, goal.Frequency,
            goal.FrequencyTarget, goal.TargetDate, goal.DeeperWhy, goal.CreatedAt
        });
    }

    private static async Task<IResult> ListGoals(
        ICurrentUser currentUser, AppDbContext db, string? date = null)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goals = await db.Goals
            .Where(g => g.UserId == user.Id && g.ArchivedAt == null)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var result = goals.Select(g =>
        {
            if (g.Type == GoalType.OneTime)
            {
                var noteCount = g.CheckIns.Count(c => c.Note is not null);
                int? daysRemaining = g.TargetDate.HasValue
                    ? g.TargetDate.Value.DayNumber - today.DayNumber
                    : null;
                var todayCheckIn = g.CheckIns.FirstOrDefault(c => c.Date == today);

                return (object)new
                {
                    g.Id,
                    g.Title,
                    g.Type,
                    g.TargetDate,
                    g.Progress,
                    g.CompletedAt,
                    g.CreatedAt,
                    DaysRemaining = daysRemaining,
                    NoteCount = noteCount,
                    CheckIn = todayCheckIn != null ? new { todayCheckIn.Completed, todayCheckIn.Note } : null
                };
            }
            else
            {
                var (current, longest) = ComputeStreaks(g.CheckIns, today);
                return (object)new
                {
                    g.Id,
                    g.Title,
                    g.Type,
                    g.Frequency,
                    g.FrequencyTarget,
                    g.CreatedAt,
                    CurrentStreak = current,
                    LongestStreak = longest
                };
            }
        });

        return Results.Ok(result);
    }

    private static async Task<IResult> GetToday(
        ICurrentUser currentUser, AppDbContext db, string? date = null)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var goals = await db.Goals
            .Where(g => g.UserId == user.Id && g.ArchivedAt == null && g.Type == GoalType.Recurring)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync();

        var result = goals.Select(g =>
        {
            var (current, longest) = ComputeStreaks(g.CheckIns, today);
            var todayCheckIn = g.CheckIns.FirstOrDefault(c => c.Date == today);
            return new
            {
                g.Id,
                g.Title,
                CurrentStreak = current,
                LongestStreak = longest,
                CheckIn = todayCheckIn != null ? new { todayCheckIn.Completed, todayCheckIn.Note } : null
            };
        });

        return Results.Ok(result);
    }

    private static async Task<IResult> GetGoal(
        Guid id, ICurrentUser currentUser, AppDbContext db)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == user.Id);

        if (goal is null) return Results.NotFound();

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        if (goal.Type == GoalType.OneTime)
        {
            var noteCount = goal.CheckIns.Count(c => c.Note is not null);
            int? daysRemaining = goal.TargetDate.HasValue
                ? goal.TargetDate.Value.DayNumber - today.DayNumber
                : null;

            return Results.Ok(new
            {
                goal.Id, goal.Title, goal.Type, goal.TargetDate, goal.DeeperWhy,
                goal.Progress, goal.CompletedAt, goal.CreatedAt,
                DaysRemaining = daysRemaining, NoteCount = noteCount
            });
        }
        else
        {
            var (current, longest) = ComputeStreaks(goal.CheckIns, today);
            return Results.Ok(new
            {
                goal.Id, goal.Title, goal.Type, goal.Frequency,
                goal.FrequencyTarget, goal.DeeperWhy, goal.CreatedAt,
                CurrentStreak = current, LongestStreak = longest
            });
        }
    }

    private static async Task<IResult> UpdateGoal(
        Guid id, ICurrentUser currentUser, AppDbContext db, UpdateGoalRequest body)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == user.Id);

        if (goal is null) return Results.NotFound();

        if (body.Title is not null)
        {
            if (string.IsNullOrWhiteSpace(body.Title))
                return Results.BadRequest(new { error = "Title cannot be empty." });
            goal.Title = body.Title.Trim();
        }

        if (body.Archived is true)
            goal.ArchivedAt = DateTime.UtcNow;
        else if (body.Archived is false)
            goal.ArchivedAt = null;

        if (body.Completed is true)
            goal.CompletedAt = DateTime.UtcNow;
        else if (body.Completed is false)
            goal.CompletedAt = null;

        if (body.DeeperWhy is not null)
            goal.DeeperWhy = body.DeeperWhy.Trim();

        if (body.Progress is not null)
            goal.Progress = Math.Clamp(body.Progress.Value, 0, 100);

        if (body.TargetDate is not null)
        {
            if (DateOnly.TryParse(body.TargetDate, out var parsedDate))
                goal.TargetDate = parsedDate;
            else
                return Results.BadRequest(new { error = "Invalid date format. Use yyyy-MM-dd." });
        }

        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Results.Conflict(new { error = "A goal with that title already exists." });
        }

        return Results.NoContent();
    }

    private static async Task<IResult> DeleteGoal(
        Guid id, ICurrentUser currentUser, AppDbContext db)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == user.Id);

        if (goal is null) return Results.NotFound();

        db.GoalCheckIns.RemoveRange(goal.CheckIns);
        db.Goals.Remove(goal);
        await db.SaveChangesAsync();

        return Results.NoContent();
    }

    private static async Task<IResult> CheckIn(
        Guid id, ICurrentUser currentUser, AppDbContext db, CheckInRequest body)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == user.Id);

        if (goal is null) return Results.NotFound();

        var today = body.Date is not null && DateOnly.TryParse(body.Date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.GoalCheckIns
            .FirstOrDefaultAsync(c => c.GoalId == id && c.Date == today);

        if (existing is not null)
        {
            existing.Completed = body.Completed;
            existing.Note = body.Note;
        }
        else
        {
            var checkIn = new GoalCheckIn
            {
                Id = Guid.NewGuid(),
                GoalId = id,
                Date = today,
                Completed = body.Completed,
                Note = body.Note,
                CreatedAt = DateTime.UtcNow
            };
            db.GoalCheckIns.Add(checkIn);
            existing = checkIn;
        }

        // Milestones: mark permanently completed when checked in as done
        if (goal.Type == GoalType.OneTime && body.Completed)
            goal.CompletedAt = DateTime.UtcNow;
        else if (goal.Type == GoalType.OneTime && !body.Completed)
            goal.CompletedAt = null;

        await db.SaveChangesAsync();

        return Results.Ok(new { existing.Id, existing.Date, existing.Completed, existing.Note });
    }

    private static async Task<IResult> UndoCheckIn(
        Guid id, ICurrentUser currentUser, AppDbContext db, string? date = null)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == user.Id);

        if (goal is null) return Results.NotFound();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.GoalCheckIns
            .FirstOrDefaultAsync(c => c.GoalId == id && c.Date == today);

        if (existing is null) return Results.NotFound();

        db.GoalCheckIns.Remove(existing);

        // Milestones: clear permanent completion when undone
        if (goal.Type == GoalType.OneTime)
            goal.CompletedAt = null;

        await db.SaveChangesAsync();

        return Results.NoContent();
    }

    private static async Task<IResult> GetHistory(
        Guid id, ICurrentUser currentUser, AppDbContext db,
        int page = 1, int pageSize = 30)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var goalExists = await db.Goals
            .AnyAsync(g => g.Id == id && g.UserId == user.Id);

        if (!goalExists) return Results.NotFound();

        pageSize = Math.Clamp(pageSize, 1, 100);

        var history = await db.GoalCheckIns
            .Where(c => c.GoalId == id)
            .OrderByDescending(c => c.Date)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new { c.Id, c.Date, c.Completed, c.Note, c.CreatedAt })
            .ToListAsync();

        return Results.Ok(history);
    }

    private static (int CurrentStreak, int LongestStreak) ComputeStreaks(
        ICollection<GoalCheckIn> checkIns, DateOnly today)
    {
        if (checkIns.Count == 0) return (0, 0);

        var completedDates = checkIns
            .Where(c => c.Completed)
            .Select(c => c.Date)
            .ToHashSet();

        // Current streak: count consecutive days backwards
        // If today has no check-in yet, start from yesterday (streak still alive)
        var currentStreak = 0;
        var date = completedDates.Contains(today) ? today : today.AddDays(-1);
        while (completedDates.Contains(date))
        {
            currentStreak++;
            date = date.AddDays(-1);
        }

        // Longest streak: scan all completed dates in order
        if (completedDates.Count == 0) return (0, 0);

        var sorted = completedDates.OrderBy(d => d).ToList();
        var longestStreak = 1;
        var streak = 1;

        for (var i = 1; i < sorted.Count; i++)
        {
            if (sorted[i].DayNumber - sorted[i - 1].DayNumber == 1)
            {
                streak++;
                if (streak > longestStreak) longestStreak = streak;
            }
            else
            {
                streak = 1;
            }
        }

        return (currentStreak, longestStreak);
    }
}

public record CreateGoalRequest(
    string Title,
    GoalType Type = GoalType.Recurring,
    GoalFrequency? Frequency = null,
    int? FrequencyTarget = null,
    string? TargetDate = null,
    string? DeeperWhy = null);
public record UpdateGoalRequest(string? Title, bool? Archived, bool? Completed, string? DeeperWhy = null, int? Progress = null, string? TargetDate = null);
public record CheckInRequest(bool Completed, string? Note, string? Date = null);
