namespace ShantiSangha.Core.Models;

public class GoalCheckIn
{
    public Guid Id { get; set; }
    public Guid GoalId { get; set; }
    public DateOnly Date { get; set; }
    public bool Completed { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }

    public Goal Goal { get; set; } = null!;
}
