using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Data;

public class WellnessDbContext(DbContextOptions<WellnessDbContext> options) : DbContext(options)
{
    public DbSet<VoiceEntry> VoiceEntries => Set<VoiceEntry>();
    public DbSet<DailyReflection> DailyReflections => Set<DailyReflection>();
    public DbSet<DailyJournalPrompt> DailyJournalPrompts => Set<DailyJournalPrompt>();
    public DbSet<Portrait> Portraits => Set<Portrait>();
    public DbSet<DailyReading> DailyReadings => Set<DailyReading>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<VoiceEntry>(e =>
        {
            e.Property(v => v.Status).HasConversion<string>();
        });

        modelBuilder.Entity<DailyReflection>(e =>
        {
            e.HasIndex(r => new { r.UserId, r.Date }).IsUnique();
            e.Property(r => r.Type).HasConversion<string>().HasDefaultValue(ReflectionType.Regular);
        });

        modelBuilder.Entity<DailyJournalPrompt>(e =>
        {
            e.HasIndex(p => new { p.UserId, p.Date }).IsUnique();
        });

        modelBuilder.Entity<Portrait>(e =>
        {
            e.HasIndex(p => p.UserId).IsUnique();
        });

        modelBuilder.Entity<DailyReading>(e =>
        {
            e.HasIndex(r => new { r.UserId, r.Date }).IsUnique();
        });
    }
}
