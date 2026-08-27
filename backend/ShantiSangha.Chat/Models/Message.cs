namespace ShantiSangha.Chat.Models;

public enum MessageRole { User, Assistant }

public class Message
{
    public Guid Id { get; set; }
    public Guid ConversationId { get; set; }
    public MessageRole Role { get; set; }
    public string Content { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }

    /// Opaque per-message metadata owned by the writing module (the assistant
    /// stores reminder ids + photo key here). Null for companion messages.
    /// Column is added via idempotent startup SQL — Chat has no migrations.
    public string? MetadataJson { get; set; }

    public Conversation Conversation { get; set; } = null!;
}
