using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Data;

public class WellnessDbContext(DbContextOptions<WellnessDbContext> options) : DbContext(options)
{
    public DbSet<VoiceEntry> VoiceEntries => Set<VoiceEntry>();
    public DbSet<DailyJournalPrompt> DailyJournalPrompts => Set<DailyJournalPrompt>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<VoiceEntry>(e =>
        {
            e.Property(v => v.Status).HasConversion<string>();
        });

        modelBuilder.Entity<DailyJournalPrompt>(e =>
        {
            e.HasIndex(p => new { p.UserId, p.Date }).IsUnique();
        });
    }
}
