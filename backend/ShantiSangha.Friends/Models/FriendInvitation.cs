namespace ShantiSangha.Friends.Models;

public class FriendInvitation
{
    public Guid Id { get; set; }
    public Guid InviterUserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? AcceptedAt { get; set; }
    public Guid? AcceptedByUserId { get; set; }
    public DateTime? RevokedAt { get; set; }
}
