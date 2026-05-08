namespace ShantiSangha.Chat.Models;

public class Conversation
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string? Title { get; set; }

    /// <summary>
    /// Conversation type. Single value today ("general"); kept as a string so
    /// the column can carry future routing hints without a schema change.
    /// </summary>
    public string Type { get; set; } = ConversationType.General;

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public ICollection<Message> Messages { get; set; } = [];
}

public static class ConversationType
{
    public const string General = "general";
}
