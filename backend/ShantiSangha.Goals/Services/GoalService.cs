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

    public async Task<GoalCreatedResponse> CreateAsync(
        Guid userId, CreateGoalRequest body, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(body.Title))
            throw new InvalidOperationException("Title is required.");

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
        await db.SaveChangesAsync(ct);

        return new GoalCreatedResponse(
            goal.Id, goal.Title, goal.Type.ToString(), goal.Frequency?.ToString(),
            goal.FrequencyTarget, goal.TargetDate, goal.DeeperWhy, goal.CreatedAt);
    }

    public async Task<List<object>> ListAsync(
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

        return goals.Select(g =>
        {
            if (g.Type == GoalType.OneTime)
            {
                var noteCount = g.CheckIns.Count(c => c.Note is not null);
                int? daysRemaining = g.TargetDate.HasValue
                    ? g.TargetDate.Value.DayNumber - today.DayNumber
                    : null;
                var todayCheckIn = g.CheckIns.FirstOrDefault(c => c.Date == today);

                return (object)new OneTimeGoalResponse(
                    g.Id, g.Title, g.Type.ToString(), g.TargetDate, g.Progress,
                    g.CompletedAt, g.CreatedAt, daysRemaining, noteCount,
                    todayCheckIn != null ? new CheckInResponse(todayCheckIn.Completed, todayCheckIn.Note) : null);
            }
            else
            {
                var (current, longest) = ComputeStreaks(g.CheckIns, today);
                return (object)new RecurringGoalResponse(
                    g.Id, g.Title, g.Type.ToString(), g.Frequency?.ToString(),
                    g.FrequencyTarget, g.CreatedAt, current, longest);
            }
        }).ToList();
    }

    public async Task<List<TodayGoalResponse>> GetTodayAsync(
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

        return goals.Select(g =>
        {
            var (current, longest) = ComputeStreaks(g.CheckIns, today);
            var todayCheckIn = g.CheckIns.FirstOrDefault(c => c.Date == today);
            return new TodayGoalResponse(
                g.Id, g.Title, current, longest,
                todayCheckIn != null ? new CheckInResponse(todayCheckIn.Completed, todayCheckIn.Note) : null);
        }).ToList();
    }

    public async Task<object?> GetByIdAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return null;

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        if (goal.Type == GoalType.OneTime)
        {
            var noteCount = goal.CheckIns.Count(c => c.Note is not null);
            int? daysRemaining = goal.TargetDate.HasValue
                ? goal.TargetDate.Value.DayNumber - today.DayNumber
                : null;

            return new OneTimeGoalDetailResponse(
                goal.Id, goal.Title, goal.Type.ToString(), goal.TargetDate,
                goal.DeeperWhy, goal.Progress, goal.CompletedAt, goal.CreatedAt,
                daysRemaining, noteCount);
        }
        else
        {
            var (current, longest) = ComputeStreaks(goal.CheckIns, today);
            return new RecurringGoalDetailResponse(
                goal.Id, goal.Title, goal.Type.ToString(), goal.Frequency?.ToString(),
                goal.FrequencyTarget, goal.DeeperWhy, goal.CreatedAt,
                current, longest);
        }
    }

    /// <returns>true if updated, false if not found. Throws InvalidOperationException for validation errors.</returns>
    public async Task<bool> UpdateAsync(
        Guid id, Guid userId, UpdateGoalRequest body, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return false;

        if (body.Title is not null)
        {
            if (string.IsNullOrWhiteSpace(body.Title))
                throw new InvalidOperationException("Title cannot be empty.");
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
                throw new InvalidOperationException("Invalid date format. Use yyyy-MM-dd.");
        }

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteAsync(
        Guid id, Guid userId, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .Include(g => g.Activities)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return false;

        db.GoalActivities.RemoveRange(goal.Activities);
        db.GoalCheckIns.RemoveRange(goal.CheckIns);
        db.Goals.Remove(goal);
        await db.SaveChangesAsync(ct);

        return true;
    }

    /// <returns>CheckInResult if goal exists, null if goal not found.</returns>
    public async Task<CheckInResult?> CheckInAsync(
        Guid id, Guid userId, CheckInRequest body, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return null;

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

        return new CheckInResult(existing.Id, existing.Date, existing.Completed, existing.Note);
    }

    /// <returns>true if undone, false if goal or check-in not found.</returns>
    public async Task<bool> UndoCheckInAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return false;

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.GoalCheckIns
            .FirstOrDefaultAsync(c => c.GoalId == id && c.Date == today, ct);

        if (existing is null) return false;

        db.GoalCheckIns.Remove(existing);

        if (goal.Type == GoalType.OneTime)
            goal.CompletedAt = null;

        LogActivity(id, "Undone", today.ToString("MMM d, yyyy"));

        await db.SaveChangesAsync(ct);

        return true;
    }

    /// <returns>true if reset, false if not found. Throws InvalidOperationException if not recurring.</returns>
    public async Task<bool> ResetAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .Include(g => g.CheckIns)
            .Include(g => g.Activities)
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return false;
        if (goal.Type != GoalType.Recurring)
            throw new InvalidOperationException("Only recurring goals can be reset.");

        db.GoalCheckIns.RemoveRange(goal.CheckIns);
        db.GoalActivities.RemoveRange(goal.Activities);

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);
        goal.CreatedAt = today.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);

        LogActivity(id, "Created", "History reset");
        await db.SaveChangesAsync(ct);

        return true;
    }

    public async Task<List<CheckInListItem>?> GetCheckInsAsync(
        Guid id, Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return null;

        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : DateOnly.FromDateTime(DateTime.UtcNow);
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed)
            ? fromParsed
            : new DateOnly(endDate.Year, endDate.Month, 1);

        return await db.GoalCheckIns
            .Where(c => c.GoalId == id && c.Date >= startDate && c.Date <= endDate)
            .OrderBy(c => c.Date)
            .Select(c => new CheckInListItem(c.Id, c.Date.ToString("yyyy-MM-dd"), c.Completed, c.Note))
            .ToListAsync(ct);
    }

    public async Task<List<GoalActivityResponse>?> GetHistoryAsync(
        Guid id, Guid userId, int page = 1, int pageSize = 50, CancellationToken ct = default)
    {
        var goal = await db.Goals
            .FirstOrDefaultAsync(g => g.Id == id && g.UserId == userId, ct);

        if (goal is null) return null;

        pageSize = Math.Clamp(pageSize, 1, 100);

        var activities = await db.GoalActivities
            .Where(a => a.GoalId == id)
            .OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new GoalActivityResponse(a.Id, a.Action, a.Detail, a.CreatedAt))
            .ToListAsync(ct);

        var hasCreated = await db.GoalActivities
            .AnyAsync(a => a.GoalId == id && a.Action == "Created", ct);

        if (!hasCreated)
        {
            activities.Add(new GoalActivityResponse(goal.Id, "Created", null, goal.CreatedAt));
        }

        return activities;
    }

    public async Task<JourneyResponse> GetJourneyAsync(
        Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : DateOnly.FromDateTime(DateTime.UtcNow);
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed) ? fromParsed : endDate.AddDays(-6);
        var today = endDate;

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

            return new JourneyPractice(
                g.Id, g.Title, daysCompleted, goalTotalDays, current, longest,
                Enumerable.Range(0, totalDays)
                    .Select(i => startDate.AddDays(i))
                    .Select(d => new JourneyDay(d.ToString("yyyy-MM-dd"), dates.Contains(d)))
                    .ToList());
        }).ToList();

        var completedCommitments = await db.Goals
            .Where(g => g.UserId == userId && g.Type == GoalType.OneTime
                && g.CompletedAt != null
                && DateOnly.FromDateTime(g.CompletedAt!.Value) >= startDate
                && DateOnly.FromDateTime(g.CompletedAt!.Value) <= endDate)
            .Select(g => new JourneyCompletedCommitment(g.Id, g.Title, g.CompletedAt))
            .ToListAsync(ct);

        var totalCompleted = practices.Sum(p => p.DaysCompleted);
        var totalPossible = practices.Sum(p => p.TotalDays);

        return new JourneyResponse(
            startDate.ToString("yyyy-MM-dd"),
            endDate.ToString("yyyy-MM-dd"),
            totalDays,
            practices,
            completedCommitments,
            new JourneySummary(
                totalCompleted,
                totalPossible,
                totalPossible > 0 ? Math.Round(100.0 * totalCompleted / totalPossible) : 0,
                completedCommitments.Count));
    }

    public async Task<JourneyReflectionResponse> GetJourneyReflectionAsync(
        Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : DateOnly.FromDateTime(DateTime.UtcNow);
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
            return new JourneyReflectionResponse(result.Content?.Trim());
        }
        catch
        {
            return new JourneyReflectionResponse(null);
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
