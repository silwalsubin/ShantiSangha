namespace ShantiSangha.Identity.Models;

public class Profile
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Timezone { get; set; }
    /// <summary>Local-time hour (0–23) at which the user wants their morning reflection push. Null = no morning push.</summary>
    public int? ReminderHour { get; set; }
    public bool OnboardingCompleted { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public User User { get; set; } = null!;
}
