namespace ShantiSangha.Wellness.Models;

/// <summary>
/// Determines the narrative mode of a daily reflection.
/// Regular: warm observation. Seed: plants curiosity for tomorrow.
/// Callback: references a past moment. Followup: resolves a previous seed.
/// </summary>
public enum ReflectionType
{
    Regular,
    Seed,
    Callback,
    Followup
}

public class DailyReflection
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly Date { get; set; }
    public string Content { get; set; } = string.Empty;
    public ReflectionType Type { get; set; } = ReflectionType.Regular;
    public DateTime CreatedAt { get; set; }
}
