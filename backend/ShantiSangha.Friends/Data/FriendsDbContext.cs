using Microsoft.EntityFrameworkCore;
using ShantiSangha.Friends.Models;

namespace ShantiSangha.Friends.Data;

public class FriendsDbContext(DbContextOptions<FriendsDbContext> options) : DbContext(options)
{
    public DbSet<Friendship> Friendships => Set<Friendship>();
    public DbSet<FriendInvitation> Invitations => Set<FriendInvitation>();
    public DbSet<FriendMessage> Messages => Set<FriendMessage>();

    protected override void OnModelCreating(ModelBuilder mb)
    {
        mb.Entity<Friendship>(e =>
        {
            e.HasIndex(f => new { f.UserAId, f.UserBId }).IsUnique();
            e.HasIndex(f => f.UserAId);
            e.HasIndex(f => f.UserBId);
        });

        mb.Entity<FriendInvitation>(e =>
        {
            e.Property(i => i.Token).IsRequired();
            e.HasIndex(i => i.Token).IsUnique();
            e.HasIndex(i => new { i.InviterUserId, i.AcceptedAt, i.RevokedAt });
        });

        mb.Entity<FriendMessage>(e =>
        {
            e.Property(m => m.Kind).HasConversion<string>();
            e.HasIndex(m => new { m.FriendshipId, m.SentAt });
            e.HasIndex(m => m.SenderUserId);
        });
    }
}
