using Microsoft.EntityFrameworkCore;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Practices.Contracts;
using ShantiSangha.Practices.Data;
using ShantiSangha.Practices.Models;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Practices.Services;

public class PracticeService(
    PracticesDbContext db,
    Kernel kernel,
    IEventBus eventBus) : IPracticeService
{
    private void LogActivity(Guid practiceId, string action, string? detail = null)
    {
        db.PracticeActivities.Add(new PracticeActivity
        {
            Id = Guid.NewGuid(),
            PracticeId = practiceId,
            Action = action,
            Detail = detail,
            CreatedAt = DateTime.UtcNow
        });
    }

    public async Task<PracticeCreatedResponse> CreateAsync(
        Guid userId, CreatePracticeRequest body, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(body.Title))
            throw new InvalidOperationException("Title is required.");

        var practice = new Practice
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Title = body.Title.Trim(),
            Frequency = body.Frequency,
            FrequencyTarget = body.FrequencyTarget,
            DeeperWhy = body.DeeperWhy?.Trim(),
            CreatedAt = DateTime.UtcNow
        };

        db.Practices.Add(practice);
        LogActivity(practice.Id, "Created");
        await db.SaveChangesAsync(ct);

        return new PracticeCreatedResponse(
            practice.Id, practice.Title, practice.Frequency?.ToString(),
            practice.FrequencyTarget, practice.DeeperWhy, practice.CreatedAt);
    }

    public async Task<List<PracticeResponse>> ListAsync(
        Guid userId, string? date = null, CancellationToken ct = default)
    {
        var practices = await db.Practices
            .Where(p => p.UserId == userId && p.ArchivedAt == null)
            .Include(p => p.CheckIns)
            .OrderBy(p => p.CreatedAt)
            .ToListAsync(ct);

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        return practices.Select(p =>
        {
            var (current, longest) = ComputeStreaks(p.CheckIns, today);
            var todayCheckIn = p.CheckIns.FirstOrDefault(c => c.Date == today);
            return new PracticeResponse(
                p.Id, p.Title, p.Frequency?.ToString(),
                p.FrequencyTarget, p.CreatedAt, current, longest,
                todayCheckIn != null ? new CheckInResponse(todayCheckIn.Completed, todayCheckIn.Note) : null);
        }).ToList();
    }

    public async Task<List<TodayPracticeResponse>> GetTodayAsync(
        Guid userId, string? date = null, CancellationToken ct = default)
    {
        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var practices = await db.Practices
            .Where(p => p.UserId == userId && p.ArchivedAt == null)
            .Include(p => p.CheckIns)
            .OrderBy(p => p.CreatedAt)
            .ToListAsync(ct);

        return practices.Select(p =>
        {
            var (current, longest) = ComputeStreaks(p.CheckIns, today);
            var todayCheckIn = p.CheckIns.FirstOrDefault(c => c.Date == today);
            return new TodayPracticeResponse(
                p.Id, p.Title, current, longest,
                todayCheckIn != null ? new CheckInResponse(todayCheckIn.Completed, todayCheckIn.Note) : null);
        }).ToList();
    }

    public async Task<PracticeDetailResponse?> GetByIdAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .Include(p => p.CheckIns)
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return null;

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var (current, longest) = ComputeStreaks(practice.CheckIns, today);
        return new PracticeDetailResponse(
            practice.Id, practice.Title, practice.Frequency?.ToString(),
            practice.FrequencyTarget, practice.DeeperWhy, practice.CreatedAt,
            current, longest);
    }

    /// <returns>true if updated, false if not found.</returns>
    public async Task<bool> UpdateAsync(
        Guid id, Guid userId, UpdatePracticeRequest body, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return false;

        if (body.Title is not null)
        {
            if (string.IsNullOrWhiteSpace(body.Title))
                throw new InvalidOperationException("Title cannot be empty.");
            practice.Title = body.Title.Trim();
        }

        if (body.Archived is true) practice.ArchivedAt = DateTime.UtcNow;
        else if (body.Archived is false) practice.ArchivedAt = null;

        if (body.DeeperWhy is not null)
            practice.DeeperWhy = body.DeeperWhy.Trim();

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteAsync(
        Guid id, Guid userId, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .Include(p => p.CheckIns)
            .Include(p => p.Activities)
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return false;

        db.PracticeActivities.RemoveRange(practice.Activities);
        db.PracticeCheckIns.RemoveRange(practice.CheckIns);
        db.Practices.Remove(practice);
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<CheckInResult?> CheckInAsync(
        Guid id, Guid userId, CheckInRequest body, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return null;

        var today = body.Date is not null && DateOnly.TryParse(body.Date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.PracticeCheckIns
            .FirstOrDefaultAsync(c => c.PracticeId == id && c.Date == today, ct);

        var isNew = existing is null;
        var statusChanged = existing is not null && existing.Completed != body.Completed;

        if (existing is not null)
        {
            existing.Completed = body.Completed;
            existing.Note = body.Note;
        }
        else
        {
            var checkIn = new PracticeCheckIn
            {
                Id = Guid.NewGuid(),
                PracticeId = id,
                Date = today,
                Completed = body.Completed,
                Note = body.Note,
                CreatedAt = DateTime.UtcNow
            };
            db.PracticeCheckIns.Add(checkIn);
            existing = checkIn;
        }

        if (isNew || statusChanged)
            LogActivity(id, body.Completed ? "Completed" : "Skipped", today.ToString("MMM d, yyyy"));

        await db.SaveChangesAsync(ct);

        if (body.Completed && (isNew || statusChanged))
            await eventBus.PublishAsync(new PracticeCheckedInEvent(userId, today, true), ct);

        return new CheckInResult(existing.Id, existing.Date, existing.Completed, existing.Note);
    }

    public async Task<bool> UndoCheckInAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return false;

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var existing = await db.PracticeCheckIns
            .FirstOrDefaultAsync(c => c.PracticeId == id && c.Date == today, ct);
        if (existing is null) return false;

        db.PracticeCheckIns.Remove(existing);
        LogActivity(id, "Undone", today.ToString("MMM d, yyyy"));
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> ResetAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .Include(p => p.CheckIns)
            .Include(p => p.Activities)
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return false;

        db.PracticeCheckIns.RemoveRange(practice.CheckIns);
        db.PracticeActivities.RemoveRange(practice.Activities);

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);
        practice.CreatedAt = today.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);

        LogActivity(id, "Created", "History reset");
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<List<CheckInListItem>?> GetCheckInsAsync(
        Guid id, Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return null;

        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : DateOnly.FromDateTime(DateTime.UtcNow);
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed)
            ? fromParsed
            : new DateOnly(endDate.Year, endDate.Month, 1);

        return await db.PracticeCheckIns
            .Where(c => c.PracticeId == id && c.Date >= startDate && c.Date <= endDate)
            .OrderBy(c => c.Date)
            .Select(c => new CheckInListItem(c.Id, c.Date.ToString("yyyy-MM-dd"), c.Completed, c.Note))
            .ToListAsync(ct);
    }

    public async Task<List<PracticeActivityResponse>?> GetHistoryAsync(
        Guid id, Guid userId, int page = 1, int pageSize = 50, CancellationToken ct = default)
    {
        var practice = await db.Practices
            .FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct);
        if (practice is null) return null;

        pageSize = Math.Clamp(pageSize, 1, 100);

        var activities = await db.PracticeActivities
            .Where(a => a.PracticeId == id)
            .OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new PracticeActivityResponse(a.Id, a.Action, a.Detail, a.CreatedAt))
            .ToListAsync(ct);

        var hasCreated = await db.PracticeActivities
            .AnyAsync(a => a.PracticeId == id && a.Action == "Created", ct);

        if (!hasCreated)
            activities.Add(new PracticeActivityResponse(practice.Id, "Created", null, practice.CreatedAt));

        return activities;
    }

    public async Task<JourneyResponse> GetJourneyAsync(
        Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : DateOnly.FromDateTime(DateTime.UtcNow);
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed) ? fromParsed : endDate.AddDays(-6);
        var today = endDate;

        var practices = await db.Practices
            .Where(p => p.UserId == userId && p.ArchivedAt == null)
            .Include(p => p.CheckIns)
            .OrderBy(p => p.CreatedAt)
            .ToListAsync(ct);

        var totalDays = endDate.DayNumber - startDate.DayNumber + 1;
        var completedCheckIns = await db.PracticeCheckIns
            .Where(c => practices.Select(p => p.Id).Contains(c.PracticeId)
                && c.Date >= startDate && c.Date <= endDate && c.Completed)
            .Select(c => new { c.PracticeId, c.Date })
            .ToListAsync(ct);

        var completedSet = completedCheckIns
            .GroupBy(c => c.PracticeId)
            .ToDictionary(g => g.Key, g => g.Select(c => c.Date).ToHashSet());

        var journeyPractices = practices.Select(p =>
        {
            var dates = completedSet.GetValueOrDefault(p.Id) ?? new HashSet<DateOnly>();
            var daysCompleted = dates.Count;
            var (current, longest) = ComputeStreaks(p.CheckIns, today);

            var practiceCreatedDate = DateOnly.FromDateTime(p.CreatedAt);
            var effectiveStart = practiceCreatedDate > startDate ? practiceCreatedDate : startDate;
            var practiceTotalDays = Math.Max(0, endDate.DayNumber - effectiveStart.DayNumber + 1);

            return new JourneyPractice(
                p.Id, p.Title, daysCompleted, practiceTotalDays, current, longest,
                Enumerable.Range(0, totalDays)
                    .Select(i => startDate.AddDays(i))
                    .Select(d => new JourneyDay(d.ToString("yyyy-MM-dd"), dates.Contains(d)))
                    .ToList());
        }).ToList();

        var totalCompleted = journeyPractices.Sum(p => p.DaysCompleted);
        var totalPossible = journeyPractices.Sum(p => p.TotalDays);

        return new JourneyResponse(
            startDate.ToString("yyyy-MM-dd"),
            endDate.ToString("yyyy-MM-dd"),
            totalDays,
            journeyPractices,
            new JourneySummary(
                totalCompleted,
                totalPossible,
                totalPossible > 0 ? Math.Round(100.0 * totalCompleted / totalPossible) : 0));
    }

    public async Task<JourneyReflectionResponse> GetJourneyReflectionAsync(
        Guid userId, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var endDate = to is not null && DateOnly.TryParse(to, out var toParsed) ? toParsed : DateOnly.FromDateTime(DateTime.UtcNow);
        var startDate = from is not null && DateOnly.TryParse(from, out var fromParsed) ? fromParsed : endDate.AddDays(-6);
        var totalDays = endDate.DayNumber - startDate.DayNumber + 1;

        var practices = await db.Practices
            .Where(p => p.UserId == userId && p.ArchivedAt == null)
            .Include(p => p.CheckIns.Where(c => c.Date >= startDate && c.Date <= endDate))
            .OrderBy(p => p.CreatedAt)
            .ToListAsync(ct);

        var lines = new List<string>();
        lines.Add($"Period: {startDate:MMM d} to {endDate:MMM d, yyyy} ({totalDays} days)");

        var totalDone = 0;
        var totalPossible = 0;
        foreach (var p in practices)
        {
            var practiceCreatedDate = DateOnly.FromDateTime(p.CreatedAt);
            var effectiveStart = practiceCreatedDate > startDate ? practiceCreatedDate : startDate;
            var practiceTotalDays = Math.Max(0, endDate.DayNumber - effectiveStart.DayNumber + 1);

            var done = p.CheckIns.Count(c => c.Completed);
            totalDone += done;
            totalPossible += practiceTotalDays;
            lines.Add($"- {p.Title}: {done}/{practiceTotalDays} days completed");
        }

        if (totalPossible > 0)
            lines.Add($"\nOverall: {totalDone} of {totalPossible} practices completed ({Math.Round(100.0 * totalDone / totalPossible)}%)");

        var context = string.Join("\n", lines);
        var inputHash = ComputeInputHash(context);
        var cached = await db.JourneyReflections
            .FirstOrDefaultAsync(r => r.UserId == userId
                && r.FromDate == startDate
                && r.ToDate == endDate, ct);

        if (cached is not null && cached.InputHash == inputHash)
            return new JourneyReflectionResponse(cached.Content);

        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>(AiModels.FastServiceId);
            var history = new ChatHistory("""
                You are a gentle spiritual companion narrating the user's journey.
                Given practice data and thematic context from their reflections,
                write 2-3 short sentences.

                Rules:
                - First: celebrate what was accomplished with specific numbers.
                - Then: connect the practice data to the shape of their discipline.
                - End with a warm forward-looking thought.
                - Keep it under 40 words total. No emojis, no exclamation marks.
                - Never mention what was missed. Only speak to what was done.
                """);
            history.AddUserMessage(context);
            var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);
            var content = result.Content?.Trim();

            if (!string.IsNullOrWhiteSpace(content))
            {
                if (cached is not null)
                {
                    cached.Content = content;
                    cached.InputHash = inputHash;
                    cached.CreatedAt = DateTime.UtcNow;
                }
                else
                {
                    db.JourneyReflections.Add(new JourneyReflection
                    {
                        Id = Guid.NewGuid(),
                        UserId = userId,
                        FromDate = startDate,
                        ToDate = endDate,
                        Content = content,
                        InputHash = inputHash,
                        CreatedAt = DateTime.UtcNow
                    });
                }
                await db.SaveChangesAsync(ct);
            }

            return new JourneyReflectionResponse(content);
        }
        catch
        {
            return new JourneyReflectionResponse(cached?.Content);
        }
    }

    private static string ComputeInputHash(string input)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(input);
        var hash = System.Security.Cryptography.SHA256.HashData(bytes);
        return Convert.ToHexString(hash);
    }

    internal static (int CurrentStreak, int LongestStreak) ComputeStreaks(
        ICollection<PracticeCheckIn> checkIns, DateOnly today)
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
