namespace ShantiSangha.Friends.Models;

public enum FriendMessageKind { Text, Image, Voice }

public class FriendMessage
{
    public Guid Id { get; set; }
    /// <summary>For 1:1 chats this is the friendship id. The wire-side
    /// `ConversationId` exposed in DTOs is the same value — kept under
    /// `FriendshipId` in the schema for v1 to limit blast radius, with a
    /// future migration introducing a generic `Conversation` table when
    /// group chats land.</summary>
    public Guid FriendshipId { get; set; }
    public Guid SenderUserId { get; set; }
    public Guid? ReplyToMessageId { get; set; }
    public FriendMessageKind Kind { get; set; }
    public string? Body { get; set; }
    public string? StorageKey { get; set; }
    public int? DurationMs { get; set; }
    public DateTime SentAt { get; set; }
    public DateTime? ReadAt { get; set; }
    /// <summary>Set when the sender edits the body via PUT
    /// /messages/{id}. Only populated for Text messages within the
    /// 15-minute edit window. Null otherwise.</summary>
    public DateTime? EditedAt { get; set; }
    /// <summary>Set when the sender deletes the message via DELETE
    /// /messages/{id}. Body is blanked and media in S3 is removed; the
    /// row is preserved so message ordering and audit history hold.
    /// Both clients render a "Message deleted" placeholder bubble.</summary>
    public DateTime? DeletedAt { get; set; }
}
