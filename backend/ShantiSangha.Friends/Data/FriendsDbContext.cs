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
    public DbSet<FriendshipAnnotation> FriendshipAnnotations => Set<FriendshipAnnotation>();
    public DbSet<Person> Persons => Set<Person>();
    public DbSet<Connection> Connections => Set<Connection>();
    public DbSet<ConnectionDate> ConnectionDates => Set<ConnectionDate>();
    public DbSet<ConnectionAttachment> ConnectionAttachments => Set<ConnectionAttachment>();

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

        mb.Entity<FriendshipAnnotation>(e =>
        {
            e.ToTable("FriendshipAnnotations");
            // Composite PK isolates per-side annotations: A and B each
            // get their own row keyed by (FriendshipId, OwnerUserId).
            e.HasKey(a => new { a.FriendshipId, a.OwnerUserId });
            // Owner-scoped queries — "all my annotations" — use this index
            // for the LEFT JOIN inside ListFriendsAsync.
            e.HasIndex(a => a.OwnerUserId);
        });

        mb.Entity<Person>(e =>
        {
            e.ToTable("Persons");
            // Partial unique index lives in the migration SQL (EF Core can
            // describe filtered indexes here too; we keep raw SQL as the
            // source of truth for parity with how every other migration
            // in this module is written).
            e.HasIndex(p => p.UserId);
        });

        mb.Entity<Connection>(e =>
        {
            e.ToTable("Connections");
            // Postgres text[] — Npgsql maps string[] natively. The GIN
            // index on `Circles` (defined in the migration) keeps
            // ARRAY-contains queries cheap when the iOS layer derives
            // filter chips from the union of in-use circle names.
            e.Property(c => c.Circles).HasColumnType("text[]");
            e.HasIndex(c => c.OwnerUserId);
            e.HasIndex(c => new { c.OwnerUserId, c.PersonId }).IsUnique();
            e.HasIndex(c => c.FriendshipId);
            // Teach EF about the FK to Persons so the change tracker can
            // order dependent inserts inside a single SaveChanges. Without
            // this, CreateLocalAsync's Person+Connection batch sometimes
            // inserts Connection first and trips FK_Connections_Persons.
            // Shadow nav (no property on the model) — the FK column is
            // PersonId, declared above; the migration owns the actual
            // CASCADE delete behavior.
            e.HasOne<Person>()
                .WithMany()
                .HasForeignKey(c => c.PersonId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        mb.Entity<ConnectionDate>(e =>
        {
            e.ToTable("ConnectionDates");
            // FK + per-connection list query. Cascade delete from Connections
            // is declared in the migration SQL so removing a connection
            // takes its dates with it.
            e.HasIndex(d => d.ConnectionId);
            // Store as text for forward compatibility with future
            // recurrence kinds (monthly, custom) without DB schema churn.
            e.Property(d => d.Recurrence).HasConversion<string>();
        });

        mb.Entity<ConnectionAttachment>(e =>
        {
            e.ToTable("ConnectionAttachments");
            // Per-connection listing; cascade delete from Connections is
            // declared in the migration SQL.
            e.HasIndex(a => a.ConnectionId);
            // Owner-scope index lets cleanup paths (e.g. account deletion)
            // sweep all of a user's attachments without scanning.
            e.HasIndex(a => a.OwnerUserId);
            e.Property(a => a.Kind).HasConversion<string>();
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
