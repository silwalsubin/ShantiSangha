using System.ComponentModel;
using Microsoft.SemanticKernel;
using ModelContextProtocol.Server;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Services;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools.Internal;

namespace ShantiSangha.Tools.Reminders;

[McpServerToolType]
public sealed class RemindersTool(IReminderService reminders, ICurrentUser currentUser)
{
    [McpServerTool(Name = "list_reminders")]
    [KernelFunction("list_reminders")]
    [Description(
        "Return the user's reminders, optionally filtered to a date range. " +
        "Use this when the user asks what's coming up, what they have scheduled, what reminders exist, " +
        "or before referring to a specific reminder by name. " +
        "Each result includes the reminder's label, date, recurrence, and days_remaining. " +
        "The `id` field is opaque — never read it aloud to the user.")]
    public async Task<object> ListReminders(
        [Description("Optional lower bound as a natural-language date ('today', 'next Monday', 'June 1', 'in 7 days', 'yyyy-MM-dd').")]
        string? from = null,
        [Description("Optional upper bound as a natural-language date.")]
        string? to = null,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();
        var all = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var fromDate = from is null ? (DateOnly?)null : DateParsing.Parse(from, today);
        var toDate = to is null ? (DateOnly?)null : DateParsing.Parse(to, today);

        if (from is not null && fromDate is null)
            return Error($"I couldn't understand the 'from' date: '{from}'. Try a format like 'June 10', 'next Monday', or 'yyyy-MM-dd'.");
        if (to is not null && toDate is null)
            return Error($"I couldn't understand the 'to' date: '{to}'. Try a format like 'June 10', 'next Monday', or 'yyyy-MM-dd'.");

        var filtered = all.Where(r =>
        {
            var occurrence = r.Date.AddDays(r.DaysRemaining);
            if (fromDate is not null && occurrence < fromDate) return false;
            if (toDate is not null && occurrence > toDate) return false;
            return true;
        }).Select(Project).ToList();

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

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
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
        var lookup = ReminderLookup.FindByLabel(all, label);

        if (lookup.Outcome == LookupOutcome.None)
            return Error($"No reminder matches '{label}'.");
        if (lookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(lookup.Candidates);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
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
        var lookup = ReminderLookup.FindByLabel(all, label);

        if (lookup.Outcome == LookupOutcome.None)
            return Error($"No reminder matches '{label}'.");
        if (lookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(lookup.Candidates);

        var deleted = await reminders.DeleteAsync(lookup.Match!.Id, user.Id, ct);
        return deleted
            ? new { deleted = new { label = lookup.Match!.Label, date = lookup.Match.Date.ToString("yyyy-MM-dd") } }
            : Error("That reminder no longer exists.");
    }

    private async Task<CurrentUserInfo> RequireUserAsync()
    {
        var user = await currentUser.GetAsync();
        return user ?? throw new UnauthorizedAccessException("No authenticated user on this request.");
    }

    private static object Project(ReminderResponse r) => new
    {
        id = r.Id,
        label = r.Label,
        date = r.Date.ToString("yyyy-MM-dd"),
        recurrence = r.Recurrence,
        days_remaining = r.DaysRemaining,
    };

    private static object Error(string message) => new { error = message };

    private static object Ambiguous(IReadOnlyList<ReminderResponse> candidates) => new
    {
        ambiguous = true,
        message = "More than one reminder matches that label. Ask the user which they meant.",
        candidates = candidates.Select(Project).ToList(),
    };
}
