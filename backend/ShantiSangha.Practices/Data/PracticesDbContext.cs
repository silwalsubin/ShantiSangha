using Microsoft.EntityFrameworkCore;
using ShantiSangha.Practices.Models;

namespace ShantiSangha.Practices.Data;

public class PracticesDbContext(DbContextOptions<PracticesDbContext> options) : DbContext(options)
{
    public DbSet<Practice> Practices => Set<Practice>();
    public DbSet<PracticeCheckIn> PracticeCheckIns => Set<PracticeCheckIn>();
    public DbSet<PracticeActivity> PracticeActivities => Set<PracticeActivity>();
    public DbSet<JourneyReflection> JourneyReflections => Set<JourneyReflection>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Practice>(e =>
        {
            e.HasIndex(g => g.UserId);
            e.HasIndex(g => new { g.UserId, g.Title }).IsUnique();
            e.Property(g => g.Frequency).HasConversion<string>();
        });

        modelBuilder.Entity<PracticeCheckIn>(e =>
        {
            e.HasIndex(c => c.PracticeId);
            e.HasIndex(c => new { c.PracticeId, c.Date }).IsUnique();
        });

        modelBuilder.Entity<PracticeActivity>(e =>
        {
            e.HasIndex(a => new { a.PracticeId, a.CreatedAt });
        });

        modelBuilder.Entity<JourneyReflection>(e =>
        {
            e.HasIndex(r => new { r.UserId, r.FromDate, r.ToDate }).IsUnique();
        });
    }
}
