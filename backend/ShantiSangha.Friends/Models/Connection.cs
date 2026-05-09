namespace ShantiSangha.Friends.Models;

/// The "how I know them" — owner-scoped relationship overlay between
/// `OwnerUserId` and the `Person` referenced by `PersonId`. Multiple
/// users can each have a Connection to the same Person (e.g., siblings
/// pointing at the same mom Person), but the `(OwnerUserId, PersonId)`
/// pair is unique. When `FriendshipId` is set the relationship is also
/// messageable via the existing Friendship-conversation path.
///
/// `Circles` is a free-form, owner-defined tag set ("Family", "Coworker",
/// "Yoga", etc.) — a person can belong to several circles at once. Empty
/// is allowed (no labels yet). Stored as a Postgres `text[]`.
public class Connection
{
    public Guid Id { get; set; }
    public Guid OwnerUserId { get; set; }
    public Guid PersonId { get; set; }
    public string[] Circles { get; set; } = [];
    public string? Nickname { get; set; }
    public string? PrivateNotes { get; set; }
    /// S3 object key for the owner's private avatar of this person — a
    /// "my version" picture only the owner sees. Wins over the linked
    /// Person's public avatar when set; never exposed to the linked
    /// in-app user. Stored as a key (not URL) so reads can re-presign
    /// short-lived GET URLs without persisting expiring strings.
    public string? PrivateAvatarKey { get; set; }
    public Guid? FriendshipId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
