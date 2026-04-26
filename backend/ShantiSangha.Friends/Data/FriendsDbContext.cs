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
    public DbSet<FriendRequest> Requests => Set<FriendRequest>();
    public DbSet<FriendMessageReaction> MessageReactions => Set<FriendMessageReaction>();

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
            e.HasIndex(m => m.ReplyToMessageId);
        });

        mb.Entity<FriendMessageReaction>(e =>
        {
            e.ToTable("FriendMessageReactions");
            // One reaction per user per message — the upsert path on
            // change relies on this composite primary key.
            e.HasKey(r => new { r.MessageId, r.UserId });
            // Materialization joins from FriendMessages → reactions by
            // MessageId; the PK already covers it.
            e.Property(r => r.Emoji).IsRequired();
        });

        mb.Entity<FriendRequest>(e =>
        {
            e.ToTable("FriendRequests");
            e.Property(r => r.Status).HasConversion<string>();
            // Recipient inbox query — list pending requests for a user,
            // newest first. Status filter narrows it tight.
            e.HasIndex(r => new { r.ToUserId, r.Status, r.CreatedAt });
            // Sender's outgoing list. Same shape, different role.
            e.HasIndex(r => new { r.FromUserId, r.Status, r.CreatedAt });
            // Duplicate-prevention check: "is there already a pending
            // request from A to B?" — covered by the (FromUserId, ...)
            // index above plus a service-layer guard. We don't put a
            // unique index on (From, To) because we want to allow re-sends
            // after a decline (Pending becomes Declined → user can send
            // a new Pending row).
        });
    }
}
