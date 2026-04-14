using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Data;

public class WellnessDbContext(DbContextOptions<WellnessDbContext> options) : DbContext(options)
{
    public DbSet<CopingSession> CopingSessions => Set<CopingSession>();
    public DbSet<VoiceEntry> VoiceEntries => Set<VoiceEntry>();
    public DbSet<DailyMantra> DailyMantras => Set<DailyMantra>();
    public DbSet<DailyReflection> DailyReflections => Set<DailyReflection>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<VoiceEntry>(e =>
        {
            e.Property(v => v.Status).HasConversion<string>();
        });

        modelBuilder.Entity<DailyMantra>(e =>
        {
            e.HasIndex(m => new { m.UserId, m.Date }).IsUnique();
        });

        modelBuilder.Entity<DailyReflection>(e =>
        {
            e.HasIndex(r => new { r.UserId, r.Date }).IsUnique();
        });
    }
}
