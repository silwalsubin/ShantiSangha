using Microsoft.EntityFrameworkCore;
using ShantiSangha.Memory.Models;

namespace ShantiSangha.Memory.Data;

public class MemoryDbContext(DbContextOptions<MemoryDbContext> options) : DbContext(options)
{
    public DbSet<MemoryChunk> MemoryChunks => Set<MemoryChunk>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("vector");

        modelBuilder.Entity<MemoryChunk>(e =>
        {
            e.Property(c => c.Embedding).HasColumnType("vector(1536)");
            e.Property(c => c.SourceType).HasMaxLength(32);
            e.Property(c => c.ContentHash).HasMaxLength(64);

            e.HasIndex(c => c.UserId);
            e.HasIndex(c => c.ConversationId);
            // One chunk per source row — re-index updates in place.
            e.HasIndex(c => new { c.SourceType, c.SourceId }).IsUnique();
        });
    }
}
