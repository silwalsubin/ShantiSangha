namespace ShantiSangha.Practices.Models;

public enum PracticeFrequency { Daily, Weekly }

public class Practice
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public PracticeFrequency? Frequency { get; set; }
    public int? FrequencyTarget { get; set; }
    public string? DeeperWhy { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ArchivedAt { get; set; }

    public ICollection<PracticeCheckIn> CheckIns { get; set; } = [];
    public ICollection<PracticeActivity> Activities { get; set; } = [];
}
