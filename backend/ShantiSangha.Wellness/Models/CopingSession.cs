namespace ShantiSangha.Wellness.Models;

public class CopingSession
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string ExerciseSlug { get; set; } = string.Empty; // e.g. "box-breathing", "grounding-5-4-3-2-1"
    public int DurationSeconds { get; set; }
    public string? Notes { get; set; }
    public DateTime CompletedAt { get; set; }
}
