using Microsoft.EntityFrameworkCore;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Data;
using ShantiSangha.Reminders.Models;

namespace ShantiSangha.Reminders.Services;

public class ReminderService(RemindersDbContext db) : IReminderService
{
    public async Task<ReminderResponse> CreateAsync(
        Guid userId, CreateReminderRequest body, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(body.Label))
            throw new InvalidOperationException("Label is required.");
        if (!DateOnly.TryParse(body.Date, out var date))
            throw new InvalidOperationException("Invalid date format. Use yyyy-MM-dd.");

        var recurrence = ParseRecurrence(body.Recurrence);

        var reminder = new Reminder
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Label = body.Label.Trim(),
            Date = date,
            Recurrence = recurrence,
            RemindersEnabled = body.RemindersEnabled ?? true,
            ConnectionId = body.ConnectionId,
            CreatedAt = DateTime.UtcNow,
        };

        db.Reminders.Add(reminder);
        await db.SaveChangesAsync(ct);

        return ToResponse(reminder, DateOnly.FromDateTime(DateTime.UtcNow));
    }

    public async Task<List<ReminderResponse>> ListAsync(
        Guid userId, Guid? connectionId = null, string? date = null, CancellationToken ct = default)
    {
        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var query = db.Reminders.Where(r => r.UserId == userId);
        if (connectionId is not null)
            query = query.Where(r => r.ConnectionId == connectionId);

        var reminders = await query
            .OrderBy(r => r.Date)
            .ToListAsync(ct);

        return reminders.Select(r => ToResponse(r, today)).ToList();
    }

    public async Task<ReminderResponse?> GetByIdAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var reminder = await db.Reminders
            .FirstOrDefaultAsync(r => r.Id == id && r.UserId == userId, ct);
        if (reminder is null) return null;

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        return ToResponse(reminder, today);
    }

    public async Task<bool> UpdateAsync(
        Guid id, Guid userId, UpdateReminderRequest body, CancellationToken ct = default)
    {
        var reminder = await db.Reminders
            .FirstOrDefaultAsync(r => r.Id == id && r.UserId == userId, ct);
        if (reminder is null) return false;

        if (body.Label is not null)
        {
            if (string.IsNullOrWhiteSpace(body.Label))
                throw new InvalidOperationException("Label cannot be empty.");
            reminder.Label = body.Label.Trim();
        }

        if (body.Date is not null)
        {
            if (!DateOnly.TryParse(body.Date, out var parsedDate))
                throw new InvalidOperationException("Invalid date format. Use yyyy-MM-dd.");
            reminder.Date = parsedDate;
        }

        if (body.Recurrence is not null)
            reminder.Recurrence = ParseRecurrence(body.Recurrence);

        if (body.RemindersEnabled is not null)
            reminder.RemindersEnabled = body.RemindersEnabled.Value;

        if (body.Completed is true)
            reminder.CompletedAt = DateTime.UtcNow;
        else if (body.Completed is false)
            reminder.CompletedAt = null;

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default)
    {
        var reminder = await db.Reminders
            .FirstOrDefaultAsync(r => r.Id == id && r.UserId == userId, ct);
        if (reminder is null) return false;

        db.Reminders.Remove(reminder);
        await db.SaveChangesAsync(ct);
        return true;
    }

    private static ReminderRecurrence ParseRecurrence(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return ReminderRecurrence.None;
        return input.Trim().ToLowerInvariant() switch
        {
            "yearly" => ReminderRecurrence.Yearly,
            "none" => ReminderRecurrence.None,
            _ => throw new InvalidOperationException("Recurrence must be 'none' or 'yearly'.")
        };
    }

    private static ReminderResponse ToResponse(Reminder r, DateOnly today)
    {
        // For yearly reminders, project to next occurrence (today or after).
        var nextOccurrence = r.Recurrence == ReminderRecurrence.Yearly
            ? NextYearlyOccurrence(r.Date, today)
            : r.Date;

        var daysRemaining = nextOccurrence.DayNumber - today.DayNumber;

        return new ReminderResponse(
            r.Id,
            r.Label,
            r.Date,
            r.Recurrence.ToString().ToLowerInvariant(),
            r.RemindersEnabled,
            r.ConnectionId,
            r.CompletedAt,
            r.CreatedAt,
            daysRemaining);
    }

    private static DateOnly NextYearlyOccurrence(DateOnly anchor, DateOnly today)
    {
        // Yearly: project month/day onto current year; if already past, roll to next year.
        var month = anchor.Month;
        var day = anchor.Day;

        // Feb 29 → Feb 28 in non-leap years (calendar reality).
        DateOnly Build(int year)
        {
            var maxDay = DateTime.DaysInMonth(year, month);
            return new DateOnly(year, month, Math.Min(day, maxDay));
        }

        var thisYear = Build(today.Year);
        return thisYear >= today ? thisYear : Build(today.Year + 1);
    }
}
