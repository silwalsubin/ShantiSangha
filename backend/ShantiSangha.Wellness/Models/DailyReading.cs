namespace ShantiSangha.Wellness.Models;

/// <summary>
/// A per-day Vedic reading delivered to the user as a sealed note. Generated
/// at midnight local time for each user. Every day has a reading — the user
/// chooses whether to open it. The framing varies based on the day's
/// strongest Vedic signal (panchang, dasha, natal alignment).
/// </summary>
public class DailyReading
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly Date { get; set; }
    public string Content { get; set; } = string.Empty;

    /// <summary>What framed the reading — ekadashi, purnima, amavasya,
    /// janma_nakshatra, antardasha_start, or regular.</summary>
    public string Framing { get; set; } = "regular";

    public DateTime CreatedAt { get; set; }
}
