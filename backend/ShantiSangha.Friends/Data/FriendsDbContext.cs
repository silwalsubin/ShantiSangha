using Microsoft.EntityFrameworkCore;
using ShantiSangha.Friends.Models;

namespace ShantiSangha.Friends.Data;

public class FriendsDbContext(DbContextOptions<FriendsDbContext> options) : DbContext(options)
{
    // Note: explicit ToTable() on every entity to avoid name collisions with
    // other modules' DbContexts (the Chat module already owns a "Messages"
    // table, an "Invitations" table is generic enough to want a prefix, etc.).
    // EF Core's default table name is the DbSet property name — convenient
    // but unsafe in a modular monolith with multiple DbContexts pointing at
    // the same Postgres database.
    public DbSet<Friendship> Friendships => Set<Friendship>();
    public DbSet<FriendInvitation> Invitations => Set<FriendInvitation>();
    public DbSet<FriendMessage> Messages => Set<FriendMessage>();

    protected override void OnModelCreating(ModelBuilder mb)
    {
        mb.Entity<Friendship>(e =>
        {
            e.ToTable("Friendships");
            e.HasIndex(f => new { f.UserAId, f.UserBId }).IsUnique();
            e.HasIndex(f => f.UserAId);
            e.HasIndex(f => f.UserBId);
        });

        mb.Entity<FriendInvitation>(e =>
        {
            e.ToTable("FriendInvitations");
            e.Property(i => i.Token).IsRequired();
            e.HasIndex(i => i.Token).IsUnique();
            e.HasIndex(i => new { i.InviterUserId, i.AcceptedAt, i.RevokedAt });
        });

        mb.Entity<FriendMessage>(e =>
        {
            e.ToTable("FriendMessages");
            e.Property(m => m.Kind).HasConversion<string>();
            e.HasIndex(m => new { m.FriendshipId, m.SentAt });
            e.HasIndex(m => m.SenderUserId);
        });
    }
}
