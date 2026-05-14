using Microsoft.EntityFrameworkCore;
using ShantiSangha.Notifications.Models;

namespace ShantiSangha.Notifications.Data;

public class NotificationsDbContext(DbContextOptions<NotificationsDbContext> options) : DbContext(options)
{
    public DbSet<AppNotification> Notifications => Set<AppNotification>();

    protected override void OnModelCreating(ModelBuilder mb)
    {
        mb.Entity<AppNotification>(e =>
        {
            // Module-prefixed table name to avoid collisions with the
            // existing Identity SafetyEvents / anything else in the same
            // Postgres database. Same lesson the Friends module learned
            // the hard way.
            e.ToTable("AppNotifications");

            // Unread-badge query: count rows where RecipientUserId = me AND
            // ViewedAt IS NULL. The composite index covers it directly.
            e.HasIndex(n => new { n.RecipientUserId, n.ViewedAt });

            // Inbox list query: most recent first for the recipient.
            e.HasIndex(n => new { n.RecipientUserId, n.CreatedAt });
        });
    }
}
