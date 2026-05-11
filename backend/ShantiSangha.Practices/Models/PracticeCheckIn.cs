namespace ShantiSangha.Practices.Models;

public class PracticeCheckIn
{
    public Guid Id { get; set; }
    public Guid PracticeId { get; set; }
    public DateOnly Date { get; set; }
    public bool Completed { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }

    public Practice Practice { get; set; } = null!;
}
