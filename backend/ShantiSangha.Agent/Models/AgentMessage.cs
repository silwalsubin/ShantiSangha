namespace ShantiSangha.Agent.Models;

public enum AgentMessageRole { User, Assistant }

public class AgentMessage
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public AgentMessageRole Role { get; set; }
    public string Content { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }

    /// <summary>
    /// JSON-encoded list of resource IDs the assistant referenced this
    /// turn (currently <c>{ "reminderIds": [...] }</c>). Null for user
    /// messages and for assistant messages that didn't trigger an inline
    /// card surface. The client expands these on history load to render
    /// live cards alongside the prose.
    /// </summary>
    public string? Attachments { get; set; }

    /// <summary>
    /// S3 object key for a photo the user attached to this turn, stored so
    /// the image survives a chat reopen. Null for turns without a photo.
    /// The bytes live in the media bucket; the client fetches a presigned
    /// GET URL on history load.
    /// </summary>
    public string? ImageObjectKey { get; set; }
}
