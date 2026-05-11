namespace ShantiSangha.Reminders.Contracts;

public record CreateReminderRequest(
    string Label,
    string Date,
    string? Recurrence = null,
    bool? RemindersEnabled = null,
    Guid? ConnectionId = null);

public record UpdateReminderRequest(
    string? Label = null,
    string? Date = null,
    string? Recurrence = null,
    bool? RemindersEnabled = null,
    bool? Completed = null);

public record ReminderResponse(
    Guid Id,
    string Label,
    DateOnly Date,
    string Recurrence,
    bool RemindersEnabled,
    Guid? ConnectionId,
    DateTime? CompletedAt,
    DateTime CreatedAt,
    int DaysRemaining);
