namespace ShantiSangha.Friends.Models;

/// <summary>
/// Lifecycle of a direct in-app friend request. Distinct from
/// `FriendInvitation` — that one is shareable-link-based (token, no
/// specific recipient), this one is a direct ask from one user to
/// another via search.
/// </summary>
public enum FriendRequestStatus
{
    /// <summary>Outstanding — the recipient hasn't accepted or declined yet.</summary>
    Pending,
    /// <summary>Recipient accepted; a Friendship row was created.</summary>
    Accepted,
    /// <summary>Recipient declined. Sender can't see the decline; we just
    /// stop showing the request.</summary>
    Declined,
    /// <summary>Sender cancelled before the recipient acted. Hidden from
    /// the recipient.</summary>
    Cancelled,
}

/// <summary>
/// Direct in-app friend request — sent from one user to a specific other
/// user, found via search. Distinct from `FriendInvitation` (which is
/// token-based and shareable). Both are valid paths to a Friendship; this
/// one is the path used when both users are already on the app.
/// </summary>
public class FriendRequest
{
    public Guid Id { get; set; }
    public Guid FromUserId { get; set; }
    public Guid ToUserId { get; set; }
    public FriendRequestStatus Status { get; set; } = FriendRequestStatus.Pending;
    public DateTime CreatedAt { get; set; }
    /// <summary>Set when the request transitions out of Pending (accepted,
    /// declined, or cancelled). Lets the inbox surface "responded 3h ago"
    /// timestamps without recomputing from log streams.</summary>
    public DateTime? RespondedAt { get; set; }
}
