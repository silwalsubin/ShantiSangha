namespace ShantiSangha.Core.Models;

public enum GoalType { Recurring, OneTime }
public enum GoalFrequency { Daily, Weekly }

public class Goal
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public GoalType Type { get; set; } = GoalType.Recurring;
    public GoalFrequency? Frequency { get; set; }
    public int? FrequencyTarget { get; set; }
    public DateOnly? TargetDate { get; set; }
    public string? DeeperWhy { get; set; }
    public int Progress { get; set; } = 0;
    public DateTime? CompletedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ArchivedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<GoalCheckIn> CheckIns { get; set; } = [];
}
