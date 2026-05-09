namespace ShantiSangha.Friends.Models;

/// Owner-private keepsake attached to a Connection — a photo, video,
/// PDF, or any other file the owner wants to keep alongside that
/// person. Visible only to the Connection's owner; the linked user
/// (if any) never sees it. `Kind` is auto-derived from `ContentType`
/// so the iOS UI can split MEDIA from FILES without trusting client
/// classification.
///
/// Storage lives in the shared friends-media S3 bucket under a
/// `connections/{ownerId}/{connectionId}/...` prefix so removing a
/// Connection makes orphan cleanup straightforward.
public class ConnectionAttachment
{
    public Guid Id { get; set; }
    public Guid ConnectionId { get; set; }
    public Guid OwnerUserId { get; set; }
    public string ObjectKey { get; set; } = string.Empty;
    public string ContentType { get; set; } = string.Empty;
    public long ByteSize { get; set; }
    public string FileName { get; set; } = string.Empty;
    public ConnectionAttachmentKind Kind { get; set; } = ConnectionAttachmentKind.File;
    public string? Caption { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
