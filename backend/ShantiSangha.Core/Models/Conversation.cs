namespace ShantiSangha.Core.Models;

public class Conversation
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string? Title { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<Message> Messages { get; set; } = [];
    public ICollection<Summary> Summaries { get; set; } = [];
}
