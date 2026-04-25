namespace ShantiSangha.Friends.Models;

public enum FriendMessageKind { Text, Image, Voice }

public class FriendMessage
{
    public Guid Id { get; set; }
    public Guid FriendshipId { get; set; }
    public Guid SenderUserId { get; set; }
    public FriendMessageKind Kind { get; set; }
    public string? Body { get; set; }
    public string? StorageKey { get; set; }
    public int? DurationMs { get; set; }
    public DateTime SentAt { get; set; }
    public DateTime? ReadAt { get; set; }
}
