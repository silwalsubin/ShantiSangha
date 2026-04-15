using Microsoft.EntityFrameworkCore;
using ShantiSangha.Goals.Models;

namespace ShantiSangha.Goals.Data;

public class GoalsDbContext(DbContextOptions<GoalsDbContext> options) : DbContext(options)
{
    public DbSet<Goal> Goals => Set<Goal>();
    public DbSet<GoalCheckIn> GoalCheckIns => Set<GoalCheckIn>();
    public DbSet<GoalActivity> GoalActivities => Set<GoalActivity>();
    public DbSet<JourneyReflection> JourneyReflections => Set<JourneyReflection>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Goal>(e =>
        {
            e.HasIndex(g => g.UserId);
            e.HasIndex(g => new { g.UserId, g.Title }).IsUnique();
            e.Property(g => g.Type).HasConversion<string>();
            e.Property(g => g.Frequency).HasConversion<string>();
        });

        modelBuilder.Entity<GoalCheckIn>(e =>
        {
            e.HasIndex(c => c.GoalId);
            e.HasIndex(c => new { c.GoalId, c.Date }).IsUnique();
        });

        modelBuilder.Entity<GoalActivity>(e =>
        {
            e.HasIndex(a => new { a.GoalId, a.CreatedAt });
        });

        modelBuilder.Entity<JourneyReflection>(e =>
        {
            e.HasIndex(r => new { r.UserId, r.FromDate, r.ToDate }).IsUnique();
        });
    }
}
