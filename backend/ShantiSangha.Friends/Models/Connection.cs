namespace ShantiSangha.Friends.Models;

/// The "how I know them" — owner-scoped relationship overlay between
/// `OwnerUserId` and the `Person` referenced by `PersonId`. Multiple
/// users can each have a Connection to the same Person (e.g., siblings
/// pointing at the same mom Person), but the `(OwnerUserId, PersonId)`
/// pair is unique. When `FriendshipId` is set the relationship is also
/// messageable via the existing Friendship-conversation path.
public class Connection
{
    public Guid Id { get; set; }
    public Guid OwnerUserId { get; set; }
    public Guid PersonId { get; set; }
    public ConnectionType RelationType { get; set; }
    public string? CustomRelationLabel { get; set; }
    public string? Nickname { get; set; }
    public string? PrivateNotes { get; set; }
    public Guid? FriendshipId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
