using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Data;

public class WellnessDbContext(DbContextOptions<WellnessDbContext> options) : DbContext(options)
{
    public DbSet<MoodCheckin> MoodCheckins => Set<MoodCheckin>();
    public DbSet<CopingSession> CopingSessions => Set<CopingSession>();
    public DbSet<VoiceEntry> VoiceEntries => Set<VoiceEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<MoodCheckin>(e =>
        {
            e.HasIndex(m => new { m.UserId, m.CreatedAt });
        });

        modelBuilder.Entity<VoiceEntry>(e =>
        {
            e.Property(v => v.Status).HasConversion<string>();
        });
    }
}
