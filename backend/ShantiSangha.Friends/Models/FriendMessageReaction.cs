namespace ShantiSangha.Friends.Models;

/// <summary>
/// One emoji reaction by one user on one message. Composite primary key
/// on (MessageId, UserId) enforces "one reaction per user per message"
/// — replacing it on change is just an upsert by primary key.
///
/// Why store the user id rather than just a count: lets the materialized
/// `FriendMessageReactionSummary` flag whether the calling user has
/// reacted (drives the "highlighted pill" state on the iOS bubble) and
/// keeps the door open for showing avatars-of-reactors later.
/// </summary>
public class FriendMessageReaction
{
    public Guid MessageId { get; set; }
    public Guid UserId { get; set; }
    public string Emoji { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
