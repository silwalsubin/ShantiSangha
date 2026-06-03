namespace ShantiSangha.Reminders.Models;

public enum ReminderRecurrence { None, Yearly }

public class Reminder
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Label { get; set; } = string.Empty;
    /// Free-text notes the user keeps on this reminder. Doubles as the
    /// working surface for the reminder-scoped assistant ("plan this").
    public string? Notes { get; set; }
    public DateOnly Date { get; set; }
    public ReminderRecurrence Recurrence { get; set; } = ReminderRecurrence.None;
    public bool RemindersEnabled { get; set; } = true;
    public Guid? ConnectionId { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime CreatedAt { get; set; }

    public ICollection<ReminderCollaborator> Collaborators { get; set; }
        = new List<ReminderCollaborator>();
}
