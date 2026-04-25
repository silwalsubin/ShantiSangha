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

    // Where the user lives — captured by the LocationGate during onboarding.
    // Display strings sourced from MapKit/CoreLocation placemark fields:
    // `country`, `administrativeArea`, `locality`. All required (non-empty)
    // before the gate is satisfied, but stored nullable so backfills /
    // schema migrations can grow without breaking anything.
    public string? Country { get; set; }
    public string? State { get; set; }
    public string? City { get; set; }

    /// <summary>S3 object key for the user's avatar image. Lives in the
    /// shared friends-media bucket under `avatars/{userId}/{guid}.{ext}`.
    /// Exposed to consumers as a short-lived presigned GET URL generated at
    /// read time (see UserService.GetMeAsync) — never persist the URL.</summary>
    public string? AvatarKey { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public User User { get; set; } = null!;
}
