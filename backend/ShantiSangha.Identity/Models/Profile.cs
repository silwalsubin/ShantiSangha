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

    // Birth details — used for invisible Vedic astrology context in reflections and chat.
    // All optional. More data = richer context. Birth time enables nakshatra/lagna precision.
    public DateOnly? BirthDate { get; set; }
    /// <summary>Birth time as "HH:mm" in 24h format. Null = unknown (sun sign only).</summary>
    public string? BirthTime { get; set; }
    /// <summary>Birth place as "lat,lng" (e.g. "27.7172,85.3240"). Used for lagna/nakshatra calculation.</summary>
    public string? BirthPlace { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public User User { get; set; } = null!;
}
