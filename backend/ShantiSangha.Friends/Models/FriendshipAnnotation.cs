namespace ShantiSangha.Friends.Models;

/// Per-viewer overlay data on a friendship — nickname and private notes
/// that only the row's `OwnerUserId` can see. A and B each get their own
/// row keyed by (FriendshipId, OwnerUserId), so A's nickname for B is
/// independent of B's nickname for A.
public class FriendshipAnnotation
{
    public Guid FriendshipId { get; set; }
    public Guid OwnerUserId { get; set; }
    public string? Nickname { get; set; }
    public string? PrivateNotes { get; set; }
    public DateTime UpdatedAt { get; set; }
}
