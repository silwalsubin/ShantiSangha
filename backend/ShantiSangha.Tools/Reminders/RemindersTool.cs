using System.ComponentModel;
using Microsoft.SemanticKernel;
using ModelContextProtocol.Server;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Services;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools.Internal;

namespace ShantiSangha.Tools.Reminders;

[McpServerToolType]
public sealed class RemindersTool(
    IReminderService reminders,
    IConnectionsService connections,
    ICurrentUser currentUser,
    IProfileQueryService profileQuery,
    RemindersListSink listSink)
{
    [McpServerTool(Name = "list_reminders")]
    [KernelFunction("list_reminders")]
    [Description(
        "Return the user's reminders, optionally filtered to a date range and / or only the shared ones. " +
        "Use this when the user asks what's coming up, what they have scheduled, what reminders exist, " +
        "WHO a reminder is shared with, WHO owns it, or before referring to a specific reminder by name. " +
        "Each result includes: label, date, recurrence, days_remaining, is_shared (bool), shared_by " +
        "(owner's display name when a friend shared this reminder with the caller; null when the caller owns it), " +
        "and shared_with (array of collaborator display names on the caller's own reminders; null on reminders shared with the caller). " +
        "When the user asks specifically about shared / collaborative reminders, set shared_only: true so only those rows are returned and rendered as cards. " +
        "The `id` field is opaque — never read it aloud to the user.")]
    public async Task<object> ListReminders(
        [Description("Optional lower bound as a natural-language date ('today', 'next Monday', 'June 1', 'in 7 days', 'yyyy-MM-dd').")]
        string? from = null,
        [Description("Optional upper bound as a natural-language date.")]
        string? to = null,
        [Description("Optional. When true, return only reminders that are shared — either the caller owns it and added collaborators, OR a friend shared it with the caller. Use when the user asks about shared / collaborative reminders.")]
        bool shared_only = false,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();
        var all = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);

        var today = await GetTodayAsync(user.Id, ct);
        var fromDate = from is null ? (DateOnly?)null : DateParsing.Parse(from, today);
        var toDate = to is null ? (DateOnly?)null : DateParsing.Parse(to, today);

        if (from is not null && fromDate is null)
            return Error($"I couldn't understand the 'from' date: '{from}'. Try a format like 'June 10', 'next Monday', or 'yyyy-MM-dd'.");
        if (to is not null && toDate is null)
            return Error($"I couldn't understand the 'to' date: '{to}'. Try a format like 'June 10', 'next Monday', or 'yyyy-MM-dd'.");

        var matched = all.Where(r =>
        {
            // Completed reminders aren't "what's coming up" — they live on
            // the original chat turn as a "Done" card. Hide them from
            // future state queries so the assistant only surfaces pending
            // work.
            if (r.CompletedAt is not null) return false;
            // shared_only narrows the result to rows where there's actual
            // collaboration — either the caller has shared it out, or
            // someone else has shared it with the caller.
            if (shared_only && !r.IsSharedWithMe && r.Collaborators.Length == 0) return false;
            var occurrence = r.Date.AddDays(r.DaysRemaining);
            if (fromDate is not null && occurrence < fromDate) return false;
            if (toDate is not null && occurrence > toDate) return false;
            return true;
        }).ToList();

        // Buffer IDs so the agent loop can render these as interactive cards
        // alongside the prose. Harmless for MCP callers — the sink is just a
        // scoped list nobody else drains.
        listSink.Push(matched.Select(r => r.Id));

        var filtered = matched.Select(Project).ToList();
        return new { reminders = filtered, count = filtered.Count };
    }

    [McpServerTool(Name = "schedule_reminder")]
    [KernelFunction("schedule_reminder")]
    [Description(
        "Create a new reminder. Use this only when the user explicitly asks to be reminded or to add a reminder — " +
        "do not call this when the user is merely describing something. " +
        "Before calling, confirm in your reply the exact date you parsed so the user can correct you. " +
        "The reminder appears immediately in the user's reminders list.")]
    public async Task<object> ScheduleReminder(
        [Description("Short human label for the reminder, e.g. 'dad's birthday' or 'electric bill'. Maximum 80 characters.")]
        string label,
        [Description("When to remind — natural language ('June 10', 'next Friday', 'tomorrow') or yyyy-MM-dd.")]
        string when,
        [Description("Either 'once' (default — fires on the given date) or 'yearly' (fires every year on the same month/day).")]
        string recurrence = "once",
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        if (string.IsNullOrWhiteSpace(label))
            return Error("A reminder needs a label.");
        if (label.Length > 80)
            return Error("Label is too long. Keep it under 80 characters.");

        var today = await GetTodayAsync(user.Id, ct);
        var date = DateParsing.Parse(when, today);
        if (date is null)
            return Error($"I couldn't parse the date '{when}'. Try a format like 'June 10', 'next Monday', or 'yyyy-MM-dd'.");

        var serviceRecurrence = (recurrence?.Trim().ToLowerInvariant()) switch
        {
            null or "" or "once" or "none" => "none",
            "yearly" or "annual" or "annually" => "yearly",
            _ => null,
        };
        if (serviceRecurrence is null)
            return Error($"Recurrence must be 'once' or 'yearly', got '{recurrence}'.");

        try
        {
            var created = await reminders.CreateAsync(
                user.Id,
                new CreateReminderRequest(label.Trim(), date.Value.ToString("yyyy-MM-dd"), serviceRecurrence),
                ct);

            return new { created = Project(created) };
        }
        catch (InvalidOperationException ex)
        {
            return Error(ex.Message);
        }
    }

    [McpServerTool(Name = "reschedule_reminder")]
    [KernelFunction("reschedule_reminder")]
    [Description(
        "Move an existing reminder to a new date. The user refers to it by its label — fuzzy matching is supported. " +
        "If the label matches more than one reminder, this tool returns an ambiguity list instead of changing anything; " +
        "present the choices to the user and ask which they meant before calling again with a more specific label.")]
    public async Task<object> RescheduleReminder(
        [Description("Label or partial label of the reminder to move.")]
        string label,
        [Description("The new date — natural language or yyyy-MM-dd.")]
        string new_when,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        var all = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);
        var lookup = LabeledLookup.FindByLabel(all, r => r.Label, label);

        if (lookup.Outcome == LookupOutcome.None)
            return Error($"No reminder matches '{label}'.");
        if (lookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(lookup.Candidates);

        var today = await GetTodayAsync(user.Id, ct);
        var date = DateParsing.Parse(new_when, today);
        if (date is null)
            return Error($"I couldn't parse the date '{new_when}'.");

        try
        {
            var updated = await reminders.UpdateAsync(
                lookup.Match!.Id, user.Id,
                new UpdateReminderRequest(Date: date.Value.ToString("yyyy-MM-dd")),
                ct);

            return updated is null
                ? Error("That reminder no longer exists.")
                : new { updated = Project(updated) };
        }
        catch (InvalidOperationException ex)
        {
            return Error(ex.Message);
        }
    }

    [McpServerTool(Name = "cancel_reminder")]
    [KernelFunction("cancel_reminder")]
    [Description(
        "Delete an existing reminder. The user refers to it by its label. " +
        "Always confirm with the user in conversation before calling this tool — say which reminder you're about to delete and wait for explicit confirmation. " +
        "Only set `confirmed: true` after the user has explicitly agreed in their most recent message. " +
        "Ambiguous labels return a disambiguation list and no deletion occurs.")]
    public async Task<object> CancelReminder(
        [Description("Label or partial label of the reminder to delete.")]
        string label,
        [Description("Must be true. Set this only after the user has explicitly confirmed the deletion in conversation.")]
        bool confirmed,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        if (!confirmed)
            return Error("Confirmation required. Ask the user to confirm before calling this tool with confirmed: true.");

        var all = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);
        var lookup = LabeledLookup.FindByLabel(all, r => r.Label, label);

        if (lookup.Outcome == LookupOutcome.None)
            return Error($"No reminder matches '{label}'.");
        if (lookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(lookup.Candidates);

        var deleted = await reminders.DeleteAsync(lookup.Match!.Id, user.Id, ct);
        return deleted
            ? new { deleted = new { label = lookup.Match!.Label, date = lookup.Match.Date.ToString("yyyy-MM-dd") } }
            : Error("That reminder no longer exists.");
    }

    [McpServerTool(Name = "share_reminder")]
    [KernelFunction("share_reminder")]
    [Description(
        "Add a friend as a collaborator on an existing reminder. The collaborator gets full peer access — they can view, edit, complete, and delete the reminder, and completion is shared across everyone. " +
        "A push notification is delivered to the friend immediately. " +
        "Only the reminder's owner can change who it's shared with. " +
        "Find the reminder by label (fuzzy match) and the friend by name (fuzzy match against people in the user's circle who are also accepted ShantiSangha friends — local contacts cannot collaborate). " +
        "Before calling, confirm in your reply which reminder and which friend; restate so the user can correct you. If either is ambiguous, the tool returns a disambiguation list and makes no change.")]
    public async Task<object> ShareReminder(
        [Description("Label or partial label of the reminder to share.")]
        string label,
        [Description("Name or partial name of the friend to add as a collaborator. Must be an accepted ShantiSangha friend.")]
        string friend_name,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        var allReminders = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);
        var reminderLookup = LabeledLookup.FindByLabel(allReminders, r => r.Label, label);
        if (reminderLookup.Outcome == LookupOutcome.None)
            return Error($"No reminder matches '{label}'.");
        if (reminderLookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(reminderLookup.Candidates);

        var reminder = reminderLookup.Match!;
        if (reminder.IsSharedWithMe)
            return Error($"Only the owner can change who this reminder is shared with — it belongs to {reminder.OwnerDisplayName ?? "someone else"}.");

        var friendLookup = await FindFriendByNameAsync(user.Id, friend_name, ct);
        if (friendLookup.Outcome == LookupOutcome.None)
            return Error($"No accepted friend in your circle matches '{friend_name}'. (Local contacts who aren't on ShantiSangha can't collaborate.)");
        if (friendLookup.Outcome == LookupOutcome.Ambiguous)
            return AmbiguousFriends(friendLookup.Candidates);

        var friend = friendLookup.Match!;
        var friendUserId = friend.Person.UserId!.Value;

        var currentIds = reminder.Collaborators.Select(c => c.UserId).ToHashSet();
        if (currentIds.Contains(friendUserId))
            return Error($"{friend.Person.DisplayName} is already a collaborator on this reminder.");

        currentIds.Add(friendUserId);
        var nextIds = currentIds.ToArray();

        try
        {
            var updated = await reminders.UpdateAsync(
                reminder.Id, user.Id,
                new UpdateReminderRequest(CollaboratorUserIds: nextIds),
                ct);
            return updated is null
                ? Error("That reminder no longer exists.")
                : new { shared = Project(updated) };
        }
        catch (InvalidOperationException ex)
        {
            return Error(ex.Message);
        }
        catch (UnauthorizedAccessException ex)
        {
            return Error(ex.Message);
        }
    }

    [McpServerTool(Name = "unshare_reminder")]
    [KernelFunction("unshare_reminder")]
    [Description(
        "Remove a friend from an existing reminder's collaborator list. They lose access immediately — the reminder disappears from their list. " +
        "Only the reminder's owner can change who it's shared with. " +
        "Find the reminder by label and the friend by name; both support fuzzy matching. " +
        "Confirm with the user in conversation before calling, since the friend won't be notified — the row just quietly disappears for them.")]
    public async Task<object> UnshareReminder(
        [Description("Label or partial label of the reminder.")]
        string label,
        [Description("Name or partial name of the friend to remove from the collaborator list.")]
        string friend_name,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        var allReminders = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);
        var reminderLookup = LabeledLookup.FindByLabel(allReminders, r => r.Label, label);
        if (reminderLookup.Outcome == LookupOutcome.None)
            return Error($"No reminder matches '{label}'.");
        if (reminderLookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(reminderLookup.Candidates);

        var reminder = reminderLookup.Match!;
        if (reminder.IsSharedWithMe)
            return Error($"Only the owner can change who this reminder is shared with — it belongs to {reminder.OwnerDisplayName ?? "someone else"}.");

        if (reminder.Collaborators.Length == 0)
            return Error("That reminder isn't shared with anyone.");

        // Match against the current collaborator list directly (not all
        // friends) — the agent might say "remove Alex" when Alex isn't
        // even on this reminder, and that's worth surfacing.
        var collabsAsLookupable = reminder.Collaborators
            .Select(c => new { c.UserId, c.DisplayName })
            .ToList();
        var collabLookup = LabeledLookup.FindByLabel(collabsAsLookupable, c => c.DisplayName, friend_name);
        if (collabLookup.Outcome == LookupOutcome.None)
            return Error($"'{friend_name}' isn't a collaborator on '{reminder.Label}'.");
        if (collabLookup.Outcome == LookupOutcome.Ambiguous)
            return new
            {
                ambiguous = true,
                message = "More than one collaborator matches that name. Ask the user which they meant.",
                candidates = collabLookup.Candidates.Select(c => c.DisplayName).ToArray(),
            };

        var dropId = collabLookup.Match!.UserId;
        var dropName = collabLookup.Match!.DisplayName;
        var nextIds = reminder.Collaborators
            .Select(c => c.UserId)
            .Where(uid => uid != dropId)
            .ToArray();

        try
        {
            var updated = await reminders.UpdateAsync(
                reminder.Id, user.Id,
                new UpdateReminderRequest(CollaboratorUserIds: nextIds),
                ct);
            return updated is null
                ? Error("That reminder no longer exists.")
                : new { unshared = new { removed = dropName, reminder = Project(updated) } };
        }
        catch (InvalidOperationException ex)
        {
            return Error(ex.Message);
        }
        catch (UnauthorizedAccessException ex)
        {
            return Error(ex.Message);
        }
    }

    /// Friend-name → ConnectionResponse lookup, restricted to people in
    /// the user's circle who are also accepted ShantiSangha friends
    /// (FriendshipId + Person.UserId both set). Local contacts can't
    /// collaborate so they're filtered out before the fuzzy match —
    /// otherwise the agent might "pick" a contact and we'd fail later
    /// with a more cryptic error.
    private async Task<LookupResult<ConnectionResponse>> FindFriendByNameAsync(
        Guid userId, string name, CancellationToken ct)
    {
        var all = await connections.ListAsync(userId, ct);
        var friends = all
            .Where(c => c.FriendshipId != null && c.Person.UserId != null)
            .ToList();
        return LabeledLookup.FindByLabel(friends, c => c.Person.DisplayName, name);
    }

    private async Task<CurrentUserInfo> RequireUserAsync()
    {
        var user = await currentUser.GetAsync();
        return user ?? throw new UnauthorizedAccessException("No authenticated user on this request.");
    }

    private async Task<DateOnly> GetTodayAsync(Guid userId, CancellationToken ct)
    {
        string? tz = null;
        try { tz = await profileQuery.GetTimezoneAsync(userId, ct); }
        catch { /* best-effort — fall through to UTC */ }
        return UserClock.TodayFor(tz);
    }

    private static object Project(ReminderResponse r) => new
    {
        id = r.Id,
        label = r.Label,
        date = r.Date.ToString("yyyy-MM-dd"),
        recurrence = r.Recurrence,
        days_remaining = r.DaysRemaining,
        // Sharing context — surfaced so the agent can disclose when a
        // reminder is shared and confirm before mutating it.
        // - is_shared: true when at least one collaborator exists OR
        //   the caller is a recipient (not the owner).
        // - shared_by: owner's display name on a recipient's view, null
        //   when the caller is the owner.
        // - shared_with: array of collaborator names on the owner's
        //   view (empty if private), null on a recipient's view since
        //   recipients don't manage the share set.
        is_shared = r.IsSharedWithMe || r.Collaborators.Length > 0,
        shared_by = r.OwnerDisplayName,
        shared_with = r.IsSharedWithMe
            ? null
            : (object)r.Collaborators.Select(c => c.DisplayName).ToArray(),
    };

    private static object Error(string message) => new { error = message };

    private static object Ambiguous(IReadOnlyList<ReminderResponse> candidates) => new
    {
        ambiguous = true,
        message = "More than one reminder matches that label. Ask the user which they meant.",
        candidates = candidates.Select(Project).ToList(),
    };

    private static object AmbiguousFriends(IReadOnlyList<ConnectionResponse> candidates) => new
    {
        ambiguous = true,
        message = "More than one friend matches that name. Ask the user which they meant.",
        candidates = candidates.Select(c => new
        {
            name = c.Person.DisplayName,
            nickname = c.Nickname,
            circles = c.Circles,
        }).ToList(),
    };
}
