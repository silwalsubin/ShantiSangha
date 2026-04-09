using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Goals.Contracts;
using ShantiSangha.Goals.Data;
using ShantiSangha.Goals.Models;

namespace ShantiSangha.Goals.Services;

public class GoalService(GoalsDbContext db, Kernel kernel) : IGoalService
{
    private void LogActivity(Guid goalId, string action, string? detail = null)
    {
        db.GoalActivities.Add(new GoalActivity
        {
            Id = Guid.NewGuid(),
            GoalId = goalId,
            Action = action,
            Detail = detail,
            CreatedAt = DateTime.UtcNow
        });
    }

    public async Task<IResult> CreateAsync(
        Guid userId, CreateGoalRequest body, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(body.Title))
            return Results.BadRequest(new { error = "Title is required." });

        DateOnly? targetDate = null;
        if (body.TargetDate is not null && DateOnly.TryParse(body.TargetDate, out var parsed))
            targetDate = parsed;

        var goal = new Goal
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Title = body.Title.Trim(),
            Type = body.Type,
            Frequency = body.Frequency,
            FrequencyTarget = body.FrequencyTarget,
            TargetDate = targetDate,
            DeeperWhy = body.DeeperWhy?.Trim(),
            CreatedAt = DateTime.UtcNow
        };

        db.Goals.Add(goal);
        LogActivity(goal.Id, "Created");

        try
        {
            await db.SaveChangesAsync(ct);
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

    public async Task<IResult> ListAsync(
        Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goals = await db.Goals
            .Where(g => g.UserId == userId && g.ArchivedAt == null)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync(ct);

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

    public async Task<IResult> GetTodayAsync(
        Guid userId, string? date = null, CancellationToken ct = default)
    {
        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var goals = await db.Goals
            .Where(g => g.UserId == userId && g.ArchivedAt == null && g.Type == GoalType.Recurring)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync(ct);

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

    public async Task<IResult> GetByIdAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

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
                DaysRemaining = daysRemaining, NoteCount = noteCount,
                goal.AiNudge
            });
        }
        else
        {
            var (current, longest) = ComputeStreaks(goal.CheckIns, today);
            return Results.Ok(new
            {
                goal.Id, goal.Title, goal.Type, goal.Frequency,
                goal.FrequencyTarget, goal.DeeperWhy, goal.CreatedAt,
                CurrentStreak = current, LongestStreak = longest,
                goal.AiNudge
            });
        }
    }

    public async Task<IResult> UpdateAsync(
        Guid id, Guid userId, UpdateGoalRequest body, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

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
        {
            goal.CompletedAt = DateTime.UtcNow;
            LogActivity(id, "Completed");
        }
        else if (body.Completed is false)
            goal.CompletedAt = null;

        if (body.DeeperWhy is not null)
            goal.DeeperWhy = body.DeeperWhy.Trim();

        if (body.Progress is not null)
        {
            var oldProgress = goal.Progress;
            var newProgress = Math.Clamp(body.Progress.Value, 0, 100);
            if (oldProgress != newProgress)
            {
                goal.Progress = newProgress;
                LogActivity(id, "ProgressUpdated", $"{oldProgress}% \u2192 {newProgress}%");
            }
        }

        if (body.TargetDate is not null)
        {
            if (DateOnly.TryParse(body.TargetDate, out var parsedDate))
            {
                var oldDate = goal.TargetDate?.ToString("MMM d, yyyy");
                goal.TargetDate = parsedDate;
                LogActivity(id, "DueDateChanged", $"{oldDate ?? "none"} \u2192 {parsedDate:MMM d, yyyy}");
            }
            else
                return Results.BadRequest(new { error = "Invalid date format. Use yyyy-MM-dd." });
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            return Results.Conflict(new { error = "A goal with that title already exists." });
        }

        return Results.NoContent();
    }

    public async Task<IResult> DeleteAsync(
        Guid id, Guid userId, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .Include(g => g.Activities)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        db.GoalActivities.RemoveRange(goal.Activities);
        db.GoalCheckIns.RemoveRange(goal.CheckIns);
        db.Goals.Remove(goal);
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

    public async Task<IResult> CheckInAsync(
        Guid id, Guid userId, CheckInRequest body, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        var today = body.Date is not null && DateOnly.TryParse(body.Date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.GoalCheckIns
            .FirstOrDefaultAsync(c => c.GoalId == id && c.Date == today, ct);

        var isNew = existing is null;
        var statusChanged = existing is not null && existing.Completed != body.Completed;

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

        if (goal.Type == GoalType.OneTime && body.Completed)
            goal.CompletedAt = DateTime.UtcNow;
        else if (goal.Type == GoalType.OneTime && !body.Completed)
            goal.CompletedAt = null;

        if (isNew || statusChanged)
        {
            if (goal.Type == GoalType.OneTime)
                LogActivity(id, body.Completed ? "Completed" : "Skipped");
            else
                LogActivity(id, body.Completed ? "Completed" : "Skipped", today.ToString("MMM d, yyyy"));
        }

        await db.SaveChangesAsync(ct);

        return Results.Ok(new { existing.Id, existing.Date, existing.Completed, existing.Note });
    }

    public async Task<IResult> UndoCheckInAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.GoalCheckIns
            .FirstOrDefaultAsync(c => c.GoalId == id && c.Date == today, ct);

        if (existing is null) return Results.NotFound();

        db.GoalCheckIns.Remove(existing);

        if (goal.Type == GoalType.OneTime)
            goal.CompletedAt = null;

        LogActivity(id, "Undone", today.ToString("MMM d, yyyy"));

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

    public async Task<IResult> ResetAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .Include(g => g.Activities)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();
        if (goal.Type != GoalType.Recurring)
            return Results.BadRequest(new { error = "Only recurring goals can be reset." });

        db.GoalCheckIns.RemoveRange(goal.CheckIns);
        db.GoalActivities.RemoveRange(goal.Activities);

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);
        goal.CreatedAt = today.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        goal.AiNudge = null;
        goal.AiNudgeAt = null;

        LogActivity(id, "Created", "History reset");
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

    public async Task<IResult> GetCheckInsAsync(
        Guid id, Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : today;
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed)
            ? fromParsed
            : new DateOnly(endDate.Year, endDate.Month, 1);

        var checkIns = await db.GoalCheckIns
            .Where(c => c.GoalId == id && c.Date >= startDate && c.Date <= endDate)
            .OrderBy(c => c.Date)
            .Select(c => new { c.Id, Date = c.Date.ToString("yyyy-MM-dd"), c.Completed, c.Note })
            .ToListAsync(ct);

        return Results.Ok(checkIns);
    }

    public async Task<IResult> GetHistoryAsync(
        Guid id, Guid userId, int page = 1, int pageSize = 50, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        pageSize = Math.Clamp(pageSize, 1, 100);

        var activities = await db.GoalActivities
            .Where(a => a.GoalId == id)
            .OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new { a.Id, a.Action, a.Detail, a.CreatedAt })
            .ToListAsync(ct);

        var hasCreated = await db.GoalActivities
            .AnyAsync(a => a.GoalId == id && a.Action == "Created", ct);

        if (!hasCreated)
        {
            activities.Add(new { Id = goal.Id, Action = "Created", Detail = (string?)null, goal.CreatedAt });
        }

        return Results.Ok(activities);
    }

    public async Task<IResult> GetNudgeAsync(
        Guid id, Guid userId, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .Include(g => g.Activities.OrderByDescending(a => a.CreatedAt).Take(10))
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return Results.NotFound();

        if (goal.AiNudge is not null && goal.AiNudgeAt.HasValue
            && DateTime.UtcNow - goal.AiNudgeAt.Value < TimeSpan.FromHours(12))
        {
            return Results.Ok(new { nudge = goal.AiNudge });
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var daysSinceCreation = today.DayNumber - DateOnly.FromDateTime(goal.CreatedAt).DayNumber;
        var recentActivity = goal.Activities
            .OrderByDescending(a => a.CreatedAt)
            .Take(10)
            .Select(a => $"- {a.Action}{(a.Detail != null ? $": {a.Detail}" : "")} ({a.CreatedAt:MMM d})")
            .ToList();

        var context = $"""
            Task: "{goal.Title}"
            Type: {(goal.Type == GoalType.Recurring ? "Daily practice" : "Commitment with due date")}
            Created: {daysSinceCreation} days ago
            """;

        if (goal.Type == GoalType.Recurring)
        {
            var (current, longest) = ComputeStreaks(goal.CheckIns, today);
            context += $"\nCurrent streak: {current} days\nLongest streak: {longest} days";
        }
        else
        {
            if (goal.TargetDate.HasValue)
            {
                var daysLeft = goal.TargetDate.Value.DayNumber - today.DayNumber;
                context += $"\nDue: {(daysLeft < 0 ? $"{Math.Abs(daysLeft)} days overdue" : daysLeft == 0 ? "Today" : $"in {daysLeft} days")}";
            }
            context += $"\nProgress: {goal.Progress}%";
            if (goal.CompletedAt.HasValue) context += "\nStatus: Completed";
        }

        if (goal.DeeperWhy is not null)
            context += $"\nDeeper why: \"{goal.DeeperWhy}\"";

        if (recentActivity.Count > 0)
            context += $"\n\nRecent activity:\n{string.Join("\n", recentActivity)}";

        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("""
                You are a gentle spiritual companion. Given a user's task and its history,
                write ONE short encouraging sentence (under 20 words). Be warm, specific to
                their situation, and never generic. Reference their actual progress or patterns.
                No quotes, no emojis, no exclamation marks. Speak as a wise friend.
                """);
            history.AddUserMessage(context);
            var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);
            var nudge = result.Content?.Trim();

            if (!string.IsNullOrEmpty(nudge))
            {
                goal.AiNudge = nudge;
                goal.AiNudgeAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }

            return Results.Ok(new { nudge });
        }
        catch
        {
            return Results.Ok(new { nudge = goal.AiNudge });
        }
    }

    public async Task<IResult> GetJourneyAsync(
        Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : today;
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed) ? fromParsed : endDate.AddDays(-6);

        var goals = await db.Goals
            .Where(g => g.UserId == userId && g.ArchivedAt == null && g.Type == GoalType.Recurring)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync(ct);

        var totalDays = endDate.DayNumber - startDate.DayNumber + 1;
        var completedCheckIns = await db.GoalCheckIns
            .Where(c => goals.Select(g => g.Id).Contains(c.GoalId)
                && c.Date >= startDate && c.Date <= endDate && c.Completed)
            .Select(c => new { c.GoalId, c.Date })
            .ToListAsync(ct);

        var completedSet = completedCheckIns
            .GroupBy(c => c.GoalId)
            .ToDictionary(g => g.Key, g => g.Select(c => c.Date).ToHashSet());

        var practices = goals.Select(g =>
        {
            var dates = completedSet.GetValueOrDefault(g.Id) ?? new HashSet<DateOnly>();
            var daysCompleted = dates.Count;
            var (current, longest) = ComputeStreaks(g.CheckIns, today);

            var goalCreatedDate = DateOnly.FromDateTime(g.CreatedAt);
            var effectiveStart = goalCreatedDate > startDate ? goalCreatedDate : startDate;
            var goalTotalDays = Math.Max(0, endDate.DayNumber - effectiveStart.DayNumber + 1);

            return new
            {
                g.Id,
                g.Title,
                DaysCompleted = daysCompleted,
                TotalDays = goalTotalDays,
                CurrentStreak = current,
                LongestStreak = longest,
                Days = Enumerable.Range(0, totalDays)
                    .Select(i => startDate.AddDays(i))
                    .Select(d => new { Date = d.ToString("yyyy-MM-dd"), Completed = dates.Contains(d) })
                    .ToList()
            };
        }).ToList();

        var completedCommitments = await db.Goals
            .Where(g => g.UserId == userId && g.Type == GoalType.OneTime
                && g.CompletedAt != null
                && DateOnly.FromDateTime(g.CompletedAt!.Value) >= startDate
                && DateOnly.FromDateTime(g.CompletedAt!.Value) <= endDate)
            .Select(g => new { g.Id, g.Title, g.CompletedAt })
            .ToListAsync(ct);

        var totalCompleted = practices.Sum(p => p.DaysCompleted);
        var totalPossible = practices.Sum(p => p.TotalDays);

        return Results.Ok(new
        {
            From = startDate.ToString("yyyy-MM-dd"),
            To = endDate.ToString("yyyy-MM-dd"),
            TotalDays = totalDays,
            Practices = practices,
            CompletedCommitments = completedCommitments,
            Summary = new
            {
                PracticesCompleted = totalCompleted,
                PracticesPossible = totalPossible,
                CompletionRate = totalPossible > 0 ? Math.Round(100.0 * totalCompleted / totalPossible) : 0,
                CommitmentsFinished = completedCommitments.Count
            }
        });
    }

    public async Task<IResult> GetJourneyReflectionAsync(
        Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : today;
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed) ? fromParsed : endDate.AddDays(-6);
        var totalDays = endDate.DayNumber - startDate.DayNumber + 1;

        var goals = await db.Goals
            .Where(g => g.UserId == userId && g.ArchivedAt == null && g.Type == GoalType.Recurring)
            .Include(g => g.CheckIns.Where(c => c.Date >= startDate && c.Date <= endDate))
            .OrderBy(g => g.CreatedAt)
            .ToListAsync(ct);

        var lines = new List<string>();
        lines.Add($"Period: {startDate:MMM d} to {endDate:MMM d, yyyy} ({totalDays} days)");

        var totalDone = 0;
        var totalPossible = 0;
        foreach (var g in goals)
        {
            var goalCreatedDate = DateOnly.FromDateTime(g.CreatedAt);
            var effectiveStart = goalCreatedDate > startDate ? goalCreatedDate : startDate;
            var goalTotalDays = Math.Max(0, endDate.DayNumber - effectiveStart.DayNumber + 1);

            var done = g.CheckIns.Count(c => c.Completed);
            totalDone += done;
            totalPossible += goalTotalDays;
            lines.Add($"- {g.Title}: {done}/{goalTotalDays} days completed");
        }

        if (totalPossible > 0)
            lines.Add($"\nOverall: {totalDone} of {totalPossible} practices completed ({Math.Round(100.0 * totalDone / totalPossible)}%)");

        var completedCommitments = await db.Goals
            .Where(g => g.UserId == userId && g.Type == GoalType.OneTime
                && g.CompletedAt != null
                && DateOnly.FromDateTime(g.CompletedAt!.Value) >= startDate
                && DateOnly.FromDateTime(g.CompletedAt!.Value) <= endDate)
            .Select(g => g.Title)
            .ToListAsync(ct);

        if (completedCommitments.Count > 0)
            lines.Add($"\nCommitments finished: {string.Join(", ", completedCommitments)}");

        var context = string.Join("\n", lines);

        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("""
                You are a gentle spiritual companion. Given practice data, write exactly 2 short sentences.
                First sentence: celebrate what was accomplished — be specific about which practices and numbers.
                Second sentence: one warm forward-looking thought.
                Keep it under 30 words total. No emojis, no exclamation marks, no filler words.
                Never mention what was missed. Only speak to what was done.
                """);
            history.AddUserMessage(context);
            var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);
            return Results.Ok(new { reflection = result.Content?.Trim() });
        }
        catch
        {
            return Results.Ok(new { reflection = (string?)null });
        }
    }

    internal static (int CurrentStreak, int LongestStreak) ComputeStreaks(
        ICollection<GoalCheckIn> checkIns, DateOnly today)
    {
        if (checkIns.Count == 0) return (0, 0);

        var completedDates = checkIns
            .Where(c => c.Completed)
            .Select(c => c.Date)
            .ToHashSet();

        var currentStreak = 0;
        var date = completedDates.Contains(today) ? today : today.AddDays(-1);
        while (completedDates.Contains(date))
        {
            currentStreak++;
            date = date.AddDays(-1);
        }

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
