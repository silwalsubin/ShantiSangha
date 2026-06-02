using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Data;
using ShantiSangha.Reminders.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Reminders.Services;

public class ReminderService(
    RemindersDbContext db,
    IFriendsQueryService friendsQuery,
    IProfileQueryService profiles,
    INotificationService notifications,
    IPushNotificationService push,
    ILogger<ReminderService> logger) : IReminderService
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

        var addedCollaboratorIds = new List<Guid>();
        if (body.CollaboratorUserIds is { Length: > 0 })
        {
            addedCollaboratorIds = await ApplyCollaboratorsAsync(
                reminder, userId, body.CollaboratorUserIds, ct);
        }

        await db.SaveChangesAsync(ct);

        // Fire-and-forget notifications for the newly-shared-with friends.
        await NotifyCollaboratorsAddedAsync(reminder, userId, addedCollaboratorIds, ct);

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

        var contentChanged = false;

        if (body.Label is not null)
        {
            if (string.IsNullOrWhiteSpace(body.Label))
                throw new InvalidOperationException("Label cannot be empty.");
            reminder.Label = body.Label.Trim();
            contentChanged = true;
        }

        if (body.Date is not null)
        {
            if (!DateOnly.TryParse(body.Date, out var parsedDate))
                throw new InvalidOperationException("Invalid date format. Use yyyy-MM-dd.");
            reminder.Date = parsedDate;
            contentChanged = true;
        }

        if (body.Recurrence is not null)
        {
            reminder.Recurrence = ParseRecurrence(body.Recurrence);
            contentChanged = true;
        }

        if (body.RemindersEnabled is not null)
        {
            reminder.RemindersEnabled = body.RemindersEnabled.Value;
            contentChanged = true;
        }

        if (body.Completed is true)
        {
            reminder.CompletedAt = DateTime.UtcNow;
            contentChanged = true;
        }
        else if (body.Completed is false)
        {
            reminder.CompletedAt = null;
            contentChanged = true;
        }

        var addedCollaboratorIds = new List<Guid>();
        if (body.CollaboratorUserIds is not null)
        {
            // Only the owner may change the collaborator set. A peer
            // collaborator who tries gets a 403 surfaced as
            // UnauthorizedAccessException → caught by the controller.
            if (reminder.UserId != userId)
                throw new UnauthorizedAccessException(
                    "Only the reminder owner can change collaborators.");

            addedCollaboratorIds = await ApplyCollaboratorsAsync(
                reminder, userId, body.CollaboratorUserIds, ct);
        }

        await db.SaveChangesAsync(ct);

        // Newly-added collaborators get the bell-inbox row + alert push.
        await NotifyCollaboratorsAddedAsync(reminder, userId, addedCollaboratorIds, ct);

        // Everyone else with access (owner + existing collaborators minus
        // the actor) gets a silent push so their open client refreshes.
        // Skip when only the collaborator set was edited and no actual
        // reminder content changed — the new-collaborator path above
        // already covers the people who care.
        if (contentChanged)
        {
            await NotifyReminderChangedAsync(reminder, actorUserId: userId, ct);
        }

        return await ToResponseAsync(reminder, userId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
    }

    public async Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default)
    {
        // Either owner or collaborator can delete — peer access per
        // product decision. Cascade on Reminders.Id wipes the collaborator
        // join rows automatically.
        var reminder = await db.Reminders
            .Include(r => r.Collaborators)
            .FirstOrDefaultAsync(r => r.Id == id
                && (r.UserId == userId
                    || r.Collaborators.Any(c => c.UserId == userId)), ct);
        if (reminder is null) return false;

        // Snapshot participants BEFORE delete — cascade removes collaborator
        // rows, and we still want to ping everyone else's clients so the
        // row disappears from their Home on next refresh.
        var participantIds = ParticipantIds(reminder).Where(uid => uid != userId).ToList();

        db.Reminders.Remove(reminder);
        await db.SaveChangesAsync(ct);

        await NotifyReminderDeletedAsync(reminder.Id, participantIds, ct);
        return true;
    }

    // ── Collaborator diff ────────────────────────────────────────────

    /// Validates that every requested collaborator is an accepted friend
    /// of the owner, then diffs against the current set and inserts /
    /// removes rows. Mutates `reminder.Collaborators` so the caller's
    /// follow-up `SaveChangesAsync` persists everything atomically.
    /// Returns the list of newly-added user IDs so the caller can fire
    /// notifications post-commit.
    private async Task<List<Guid>> ApplyCollaboratorsAsync(
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

        // Add rows for any newly-requested IDs and track them for notify.
        var added = new List<Guid>();
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
            added.Add(addId);
        }
        return added;
    }

    // ── Notification fanouts ─────────────────────────────────────────

    /// Bell-inbox row + alert push for friends who were just added as
    /// collaborators. Mirrors the friend_request_accepted pattern in
    /// FriendRequestsService — try/catch every external call so a
    /// notification failure never breaks the write.
    private async Task NotifyCollaboratorsAddedAsync(
        Reminder reminder,
        Guid actorUserId,
        IReadOnlyList<Guid> addedUserIds,
        CancellationToken ct)
    {
        if (addedUserIds.Count == 0) return;

        var actorName = await profiles.GetDisplayNameAsync(actorUserId, ct) ?? "Someone";
        var actorAvatar = await profiles.GetAvatarInfoAsync(actorUserId, ct);

        foreach (var recipientId in addedUserIds)
        {
            try
            {
                await notifications.EnqueueAsync(
                    recipientUserId: recipientId,
                    type: "reminder_shared",
                    payload: new
                    {
                        reminderId = reminder.Id,
                        reminderLabel = reminder.Label,
                        byUserId = actorUserId,
                        byDisplayName = actorName,
                        byAvatarUrl = actorAvatar.AvatarUrl
                    },
                    ct: ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Failed to enqueue reminder_shared inbox row for reminder {ReminderId} → user {UserId}",
                    reminder.Id, recipientId);
            }

            // Badge = the recipient's full unread inbox count, queried
            // AFTER the enqueue so the new row is included. Matches the
            // pattern used for friend_request_accepted.
            int badge;
            try { badge = await notifications.GetUnreadCountAsync(recipientId, ct); }
            catch { badge = 1; }

            try
            {
                await push.SendAlertPushAsync(
                    userId: recipientId,
                    title: $"{actorName} shared a reminder",
                    body: reminder.Label,
                    data: new Dictionary<string, string>
                    {
                        ["type"] = "reminder_shared",
                        ["reminderId"] = reminder.Id.ToString()
                    },
                    badge: badge,
                    ct: ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Failed to send reminder_shared alert push for reminder {ReminderId} → user {UserId}",
                    reminder.Id, recipientId);
            }
        }
    }

    /// Silent push to every other participant when a shared reminder's
    /// content changes (label, date, recurrence, completion). The
    /// existing iOS `SilentPushHandler` already refreshes the reminder
    /// list on any silent push, so we only need a stable `type` for
    /// telemetry — no payload data required by the client.
    private async Task NotifyReminderChangedAsync(
        Reminder reminder, Guid actorUserId, CancellationToken ct)
    {
        var participants = ParticipantIds(reminder).Where(uid => uid != actorUserId).ToList();
        // Private reminder with no collaborators → nothing to fan out.
        if (participants.Count == 0) return;

        foreach (var uid in participants)
        {
            try
            {
                await push.SendSilentPushAsync(
                    userId: uid,
                    data: new Dictionary<string, string>
                    {
                        ["type"] = "reminder_changed",
                        ["reminderId"] = reminder.Id.ToString()
                    },
                    ct: ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Failed to send reminder_changed silent push for reminder {ReminderId} → user {UserId}",
                    reminder.Id, uid);
            }
        }
    }

    /// Mirror of NotifyReminderChangedAsync, but for the delete path —
    /// participants snapshot is taken BEFORE the cascade so we can still
    /// reach everyone who lost access.
    private async Task NotifyReminderDeletedAsync(
        Guid reminderId, IReadOnlyList<Guid> participantIds, CancellationToken ct)
    {
        if (participantIds.Count == 0) return;
        foreach (var uid in participantIds)
        {
            try
            {
                await push.SendSilentPushAsync(
                    userId: uid,
                    data: new Dictionary<string, string>
                    {
                        ["type"] = "reminder_changed",
                        ["reminderId"] = reminderId.ToString(),
                        ["deleted"] = "true"
                    },
                    ct: ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Failed to send reminder_changed (deleted) silent push for reminder {ReminderId} → user {UserId}",
                    reminderId, uid);
            }
        }
    }

    /// Everyone with access to the reminder: owner + every collaborator.
    /// De-duped to a HashSet so callers can subtract the actor with `.Where`.
    private static HashSet<Guid> ParticipantIds(Reminder reminder)
    {
        var set = new HashSet<Guid> { reminder.UserId };
        foreach (var c in reminder.Collaborators) set.Add(c.UserId);
        return set;
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

        // Yearly reminders only "complete" for one cycle. If the recorded
        // dismissal sits before the most-recently-passed anniversary, that
        // cycle is over and the next occurrence should surface as pending
        // again — Home filters on completedAt == null, so blanking it here
        // is enough to reanimate the row. The DB keeps the historical
        // timestamp; the next dismissal just overwrites it.
        var effectiveCompletedAt = r.CompletedAt;
        if (effectiveCompletedAt is not null
            && r.Recurrence == ReminderRecurrence.Yearly)
        {
            var mostRecentPast = nextOccurrence.AddYears(-1);
            if (DateOnly.FromDateTime(effectiveCompletedAt.Value) < mostRecentPast)
            {
                effectiveCompletedAt = null;
            }
        }

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
        string? ownerAvatarUrl = null;
        if (isSharedWithMe && profileCache.TryGetValue(r.UserId, out var owner))
        {
            ownerDisplayName = owner.DisplayName;
            ownerAvatarUrl = owner.AvatarUrl;
        }

        return new ReminderResponse(
            r.Id,
            r.Label,
            r.Date,
            r.Recurrence.ToString().ToLowerInvariant(),
            r.RemindersEnabled,
            r.ConnectionId,
            effectiveCompletedAt,
            r.CreatedAt,
            daysRemaining,
            collaborators,
            isSharedWithMe,
            ownerDisplayName,
            ownerAvatarUrl);
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
