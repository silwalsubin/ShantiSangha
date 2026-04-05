namespace ShantiSangha.Core.Models;

public class GoalActivity
{
    public Guid Id { get; set; }
    public Guid GoalId { get; set; }
    public string Action { get; set; } = string.Empty; // Created, Completed, Skipped, ProgressUpdated, DueDateChanged, Undone
    public string? Detail { get; set; } // e.g. "60% → 80%", "Apr 10 → Apr 15"
    public DateTime CreatedAt { get; set; }

    public Goal Goal { get; set; } = null!;
}
