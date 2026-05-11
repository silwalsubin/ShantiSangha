namespace ShantiSangha.Practices.Models;

public class PracticeActivity
{
    public Guid Id { get; set; }
    public Guid PracticeId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string? Detail { get; set; }
    public DateTime CreatedAt { get; set; }

    public Practice Practice { get; set; } = null!;
}
