using Microsoft.EntityFrameworkCore;
using ShantiSangha.Chess.Models;

namespace ShantiSangha.Chess.Data;

public class ChessDbContext(DbContextOptions<ChessDbContext> options) : DbContext(options)
{
    public DbSet<ChessGame> Games => Set<ChessGame>();

    protected override void OnModelCreating(ModelBuilder mb)
    {
        mb.Entity<ChessGame>(e =>
        {
            // Explicit table name — every module prefixes its tables to avoid
            // collisions in the shared Postgres database.
            e.ToTable("ChessGames");
            e.HasKey(g => g.Id);
            e.HasIndex(g => g.FriendshipId);
            e.HasIndex(g => g.WhiteUserId);
            e.HasIndex(g => g.BlackUserId);
            e.Property(g => g.Status).HasConversion<string>();
        });
    }
}
