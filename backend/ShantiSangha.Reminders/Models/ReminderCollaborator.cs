namespace ShantiSangha.Reminders.Models;

/// Join row: a friend the reminder's owner has explicitly shared this
/// reminder with. Collaborators get full peer access to the single
/// reminder (view + edit + complete + delete) — see
/// docs/features/friends.md for the privacy carve-out.
public class ReminderCollaborator
{
    public Guid ReminderId { get; set; }
    public Guid UserId { get; set; }
    public Guid AddedByUserId { get; set; }
    public DateTime AddedAt { get; set; }

    public Reminder? Reminder { get; set; }
}
