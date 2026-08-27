using Microsoft.EntityFrameworkCore;
using ShantiSangha.Chat.Models;

namespace ShantiSangha.Chat.Data;

public class ChatDbContext(DbContextOptions<ChatDbContext> options) : DbContext(options)
{
    public DbSet<Conversation> Conversations => Set<Conversation>();
    public DbSet<Message> Messages => Set<Message>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("vector");

        modelBuilder.Entity<Message>(e =>
        {
            e.Property(m => m.Role).HasConversion<string>();
            e.HasIndex(m => m.ConversationId);
            // Serves per-conversation replay windows and last-message lookups.
            // (Actual index is created by startup SQL — no migrations here.)
            e.HasIndex(m => new { m.ConversationId, m.CreatedAt });
        });

        modelBuilder.Entity<Conversation>(e =>
        {
            e.HasIndex(c => c.UserId);
        });
    }
}
