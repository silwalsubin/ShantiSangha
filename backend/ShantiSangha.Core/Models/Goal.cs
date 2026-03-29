namespace ShantiSangha.Core.Models;

public class Goal
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime? ArchivedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<GoalCheckIn> CheckIns { get; set; } = [];
}
