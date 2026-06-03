using ShantiSangha.Agent.AI;
using ShantiSangha.Reminders.Contracts;
using Xunit;

namespace ShantiSangha.AiEval.Tests.Agent;

/// <summary>
/// Deterministic guards for the reminder-scoped "Plan with assistant" system
/// prompt (<see cref="AgentSystemPrompt.BuildForReminder"/>). No LLM — these
/// just assert the prompt grounds the model in the one reminder and steers it
/// to keep the plan in the notes via the tool. CI-safe.
/// </summary>
public sealed class ScopedReminderPromptTests
{
    private static ReminderResponse Reminder(string label, string? notes, int daysRemaining) =>
        new(
            Id: Guid.NewGuid(),
            Label: label,
            Date: new DateOnly(2026, 8, 15),
            Recurrence: "none",
            RemindersEnabled: true,
            ConnectionId: null,
            CompletedAt: null,
            CreatedAt: DateTime.UtcNow,
            DaysRemaining: daysRemaining,
            Collaborators: Array.Empty<ReminderCollaboratorDto>(),
            IsSharedWithMe: false,
            OwnerDisplayName: null,
            OwnerAvatarUrl: null,
            Notes: notes);

    [Fact]
    public void GroundsTheModelInTheReminderAndNotesTool()
    {
        var today = new DateOnly(2026, 6, 2);
        var prompt = AgentSystemPrompt.BuildForReminder(
            today, "Subin", Reminder("Renew passport", notes: "Need DS-82.", daysRemaining: 74));

        // The reminder's label + its existing notes must be in context.
        Assert.Contains("Renew passport", prompt);
        Assert.Contains("Need DS-82.", prompt);
        // It must steer the model to persist the plan via the notes tool, and
        // to merge rather than clobber the user's own writing.
        Assert.Contains("update_reminder_notes", prompt);
        Assert.Contains("MERGE", prompt, StringComparison.OrdinalIgnoreCase);
        // And stay scoped to this one reminder.
        Assert.Contains("ONE specific reminder", prompt);
    }

    [Fact]
    public void FlagsAnOverdueReminder()
    {
        var today = new DateOnly(2026, 6, 2);
        var prompt = AgentSystemPrompt.BuildForReminder(
            today, "Subin", Reminder("File taxes", notes: null, daysRemaining: -5));

        Assert.Contains("overdue", prompt, StringComparison.OrdinalIgnoreCase);
        // Empty notes should read as a friendly placeholder, not blank.
        Assert.Contains("no notes yet", prompt, StringComparison.OrdinalIgnoreCase);
    }
}
