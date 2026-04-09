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
        });
    }
}
