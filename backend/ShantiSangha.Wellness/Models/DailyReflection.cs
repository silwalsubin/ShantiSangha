namespace ShantiSangha.Wellness.Models;

public class DailyReflection
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly Date { get; set; }
    public string Content { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
