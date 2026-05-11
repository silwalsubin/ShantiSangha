namespace ShantiSangha.Reminders.Models;

public enum ReminderRecurrence { None, Yearly }

public class Reminder
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Label { get; set; } = string.Empty;
    public DateOnly Date { get; set; }
    public ReminderRecurrence Recurrence { get; set; } = ReminderRecurrence.None;
    public bool RemindersEnabled { get; set; } = true;
    public Guid? ConnectionId { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime CreatedAt { get; set; }
}
