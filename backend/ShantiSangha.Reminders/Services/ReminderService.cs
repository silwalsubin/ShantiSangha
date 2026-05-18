using Microsoft.EntityFrameworkCore;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Data;
using ShantiSangha.Reminders.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Reminders.Services;

public class ReminderService(
    RemindersDbContext db,
    IFriendsQueryService friendsQuery,
    IProfileQueryService profiles) : IReminderService
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

        if (body.CollaboratorUserIds is { Length: > 0 })
        {
            await ApplyCollaboratorsAsync(reminder, userId, body.CollaboratorUserIds, ct);
        }

        await db.SaveChangesAsync(ct);

        return await ToResponseAsync(reminder, userId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
    }

    public async Task<List<ReminderResponse>> ListAsync(
        Guid userId, Guid? connectionId = null, string? date = null, CancellationToken ct = default)
    {
        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        // Owner OR collaborator. Eager-load Collaborators for the response;
        // resolving display names happens in a single batched profile call
        // below so we don't N+1 across rows.
        var query = db.Reminders
            .Include(r => r.Collaborators)
            .Where(r => r.UserId == userId
                        || r.Collaborators.Any(c => c.UserId == userId));

        if (connectionId is not null)
            query = query.Where(r => r.ConnectionId == connectionId);

        var reminders = await query
            .OrderBy(r => r.Date)
            .ToListAsync(ct);

        var profileCache = await BuildProfileCacheAsync(reminders, ct);

        return reminders
            .Select(r => ToResponse(r, userId, today, profileCache))
            .ToList();
    }

    public async Task<ReminderResponse?> GetByIdAsync(
        Guid id, Guid userId, string? date = null, CancellationToken ct = default)
    {
        var reminder = await db.Reminders
            .Include(r => r.Collaborators)
            .FirstOrDefaultAsync(r => r.Id == id
                && (r.UserId == userId
                    || r.Collaborators.Any(c => c.UserId == userId)), ct);
        if (reminder is null) return null;

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        return await ToResponseAsync(reminder, userId, today, ct);
    }

    public async Task<ReminderResponse?> UpdateAsync(
        Guid id, Guid userId, UpdateReminderRequest body, CancellationToken ct = default)
    {
        var reminder = await db.Reminders
            .Include(r => r.Collaborators)
            .FirstOrDefaultAsync(r => r.Id == id
                && (r.UserId == userId
                    || r.Collaborators.Any(c => c.UserId == userId)), ct);
        if (reminder is null) return null;

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

        if (body.CollaboratorUserIds is not null)
        {
            // Only the owner may change the collaborator set. A peer
            // collaborator who tries gets a 403 surfaced as
            // UnauthorizedAccessException → caught by the controller.
            if (reminder.UserId != userId)
                throw new UnauthorizedAccessException(
                    "Only the reminder owner can change collaborators.");

            await ApplyCollaboratorsAsync(reminder, userId, body.CollaboratorUserIds, ct);
        }

        await db.SaveChangesAsync(ct);
        return await ToResponseAsync(reminder, userId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
    }

    public async Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default)
    {
        // Either owner or collaborator can delete — peer access per
        // product decision. Cascade on Reminders.Id wipes the collaborator
        // join rows automatically.
        var reminder = await db.Reminders
            .FirstOrDefaultAsync(r => r.Id == id
                && (r.UserId == userId
                    || r.Collaborators.Any(c => c.UserId == userId)), ct);
        if (reminder is null) return false;

        db.Reminders.Remove(reminder);
        await db.SaveChangesAsync(ct);
        return true;
    }

    // ── Collaborator diff ────────────────────────────────────────────

    /// Validates that every requested collaborator is an accepted friend
    /// of the owner, then diffs against the current set and inserts /
    /// removes rows. Mutates `reminder.Collaborators` so the caller's
    /// follow-up `SaveChangesAsync` persists everything atomically.
    private async Task ApplyCollaboratorsAsync(
        Reminder reminder,
        Guid ownerUserId,
        Guid[] requestedIds,
        CancellationToken ct)
    {
        var requested = requestedIds.Where(g => g != Guid.Empty).Distinct().ToHashSet();
        // The owner can't be their own collaborator.
        requested.Remove(ownerUserId);

        if (requested.Count > 0)
        {
            var friendIds = await friendsQuery.GetFriendUserIdsAsync(ownerUserId, ct);
            var nonFriends = requested.Where(g => !friendIds.Contains(g)).ToList();
            if (nonFriends.Count > 0)
                throw new InvalidOperationException(
                    "Collaborators must be accepted friends.");
        }

        var existing = reminder.Collaborators
            .ToDictionary(c => c.UserId);

        // Remove rows that are no longer in the requested set.
        foreach (var row in existing.Values.ToList())
        {
            if (!requested.Contains(row.UserId))
            {
                db.ReminderCollaborators.Remove(row);
                reminder.Collaborators.Remove(row);
            }
        }

        // Add rows for any newly-requested IDs.
        foreach (var addId in requested)
        {
            if (existing.ContainsKey(addId)) continue;
            var row = new ReminderCollaborator
            {
                ReminderId = reminder.Id,
                UserId = addId,
                AddedByUserId = ownerUserId,
                AddedAt = DateTime.UtcNow,
            };
            db.ReminderCollaborators.Add(row);
            reminder.Collaborators.Add(row);
        }
    }

    // ── Response mapping ─────────────────────────────────────────────

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

    /// One-shot mapping path used for a single reminder (Create / Get /
    /// Update). Resolves profiles inline since N is small.
    private async Task<ReminderResponse> ToResponseAsync(
        Reminder r, Guid viewerUserId, DateOnly today, CancellationToken ct)
    {
        var ids = r.Collaborators.Select(c => c.UserId).ToHashSet();
        if (r.UserId != viewerUserId) ids.Add(r.UserId); // viewer is a collaborator → resolve owner name

        var cache = new Dictionary<Guid, (string DisplayName, string? AvatarUrl)>();
        foreach (var id in ids)
        {
            cache[id] = await ResolveProfileAsync(id, ct);
        }
        return ToResponse(r, viewerUserId, today, cache);
    }

    /// List-path mapping that uses a prebuilt batched cache so we don't
    /// re-resolve the same user across multiple reminder rows.
    private static ReminderResponse ToResponse(
        Reminder r,
        Guid viewerUserId,
        DateOnly today,
        IReadOnlyDictionary<Guid, (string DisplayName, string? AvatarUrl)> profileCache)
    {
        var nextOccurrence = r.Recurrence == ReminderRecurrence.Yearly
            ? NextYearlyOccurrence(r.Date, today)
            : r.Date;

        var daysRemaining = nextOccurrence.DayNumber - today.DayNumber;

        var collaborators = r.Collaborators
            .Select(c =>
            {
                var profile = profileCache.TryGetValue(c.UserId, out var p)
                    ? p
                    : (DisplayName: "Friend", AvatarUrl: (string?)null);
                return new ReminderCollaboratorDto(c.UserId, profile.DisplayName, profile.AvatarUrl);
            })
            .ToArray();

        var isSharedWithMe = r.UserId != viewerUserId;
        string? ownerDisplayName = null;
        if (isSharedWithMe && profileCache.TryGetValue(r.UserId, out var owner))
            ownerDisplayName = owner.DisplayName;

        return new ReminderResponse(
            r.Id,
            r.Label,
            r.Date,
            r.Recurrence.ToString().ToLowerInvariant(),
            r.RemindersEnabled,
            r.ConnectionId,
            r.CompletedAt,
            r.CreatedAt,
            daysRemaining,
            collaborators,
            isSharedWithMe,
            ownerDisplayName);
    }

    private async Task<Dictionary<Guid, (string DisplayName, string? AvatarUrl)>> BuildProfileCacheAsync(
        List<Reminder> reminders, CancellationToken ct)
    {
        var ids = new HashSet<Guid>();
        foreach (var r in reminders)
        {
            foreach (var c in r.Collaborators) ids.Add(c.UserId);
            ids.Add(r.UserId);
        }

        var cache = new Dictionary<Guid, (string DisplayName, string? AvatarUrl)>();
        foreach (var id in ids)
        {
            cache[id] = await ResolveProfileAsync(id, ct);
        }
        return cache;
    }

    private async Task<(string DisplayName, string? AvatarUrl)> ResolveProfileAsync(
        Guid userId, CancellationToken ct)
    {
        var name = await profiles.GetDisplayNameAsync(userId, ct) ?? "Friend";
        var avatar = await profiles.GetAvatarInfoAsync(userId, ct);
        return (name, avatar.AvatarUrl);
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
