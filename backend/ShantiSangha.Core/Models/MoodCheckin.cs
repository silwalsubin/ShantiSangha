namespace ShantiSangha.Core.Models;

public class MoodCheckin
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public int Score { get; set; } // 1–10
    public string? Notes { get; set; }
    public DateTime CreatedAt { get; set; }

    public User User { get; set; } = null!;
}
