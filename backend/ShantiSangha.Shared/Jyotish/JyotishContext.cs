namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// Vedic astrology context for a user on a given day.
/// This is consumed by AI prompts — never shown directly in UI.
/// </summary>
public record JyotishContext(
    /// <summary>Sidereal sun sign (Mesha, Vrishabha, etc.)</summary>
    string? SunRashi,
    /// <summary>Sidereal moon sign (if birth time is known)</summary>
    string? MoonRashi,
    /// <summary>Birth nakshatra (lunar mansion, if birth time is known)</summary>
    string? BirthNakshatra,
    /// <summary>Current moon nakshatra for today</summary>
    string CurrentNakshatra,
    /// <summary>Today's tithi (lunar day)</summary>
    string Tithi,
    /// <summary>Today's Vedic weekday (Vara)</summary>
    string Vara,
    /// <summary>Yoga for today</summary>
    string Yoga,
    /// <summary>Brief panchang note for AI context</summary>
    string PanchangSummary,
    /// <summary>Any notable transit or period context</summary>
    string? TransitNote);
