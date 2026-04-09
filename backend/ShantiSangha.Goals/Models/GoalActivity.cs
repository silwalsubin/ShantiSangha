namespace ShantiSangha.Goals.Models;

public class GoalActivity
{
    public Guid Id { get; set; }
    public Guid GoalId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string? Detail { get; set; }
    public DateTime CreatedAt { get; set; }

    public Goal Goal { get; set; } = null!;
}
