using Microsoft.EntityFrameworkCore;
using ShantiSangha.Insights.Models;

namespace ShantiSangha.Insights.Data;

public class InsightsDbContext(DbContextOptions<InsightsDbContext> options) : DbContext(options)
{
    public DbSet<SavedInsight> SavedInsights => Set<SavedInsight>();
    public DbSet<Summary> Summaries => Set<Summary>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("vector");

        modelBuilder.Entity<Summary>(e =>
        {
            e.Property(s => s.SourceType).HasConversion<string>();
        });
    }
}
